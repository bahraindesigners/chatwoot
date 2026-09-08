require 'faraday/multipart'

class Whatsapp::MediaUploadService
  IMAGE_CONTENT_TYPES = %w[image/jpeg image/png].freeze
  MAX_IMAGE_SIZE = 5.megabytes

  pattr_initialize [:channel!, :attachment!, :url!]

  def perform
    blob = attachment.file.blob
    blob.open do |file|
      if attachment.image? && IMAGE_CONTENT_TYPES.exclude?(blob.content_type)
        upload_converted_image(file)
      else
        upload(file, blob.content_type, blob.filename.to_s)
      end
    end
  rescue Faraday::Error, JSON::ParserError => e
    Rails.logger.warn("WhatsApp media upload failed for attachment #{attachment.id}: #{e.class}")
    raise CustomExceptions::WhatsappMediaUploadError, I18n.t('errors.whatsapp.media_upload_failed')
  end

  private

  def upload_converted_image(file)
    raise CustomExceptions::WhatsappMediaUploadError, I18n.t('errors.whatsapp.unsupported_image_type') unless attachment.file.blob.variable?

    # Use the configured Active Storage processor and keep the original attachment intact.
    ActiveStorage::Variation.wrap(format: :png).transform(file) do |converted_file|
      upload(converted_file, 'image/png', "#{attachment.file.filename.base}.png")
    end
  end

  def upload(file, content_type, filename)
    raise CustomExceptions::WhatsappMediaUploadError, I18n.t('errors.whatsapp.image_too_large') if attachment.image? && file.size > MAX_IMAGE_SIZE

    response = connection.post(url, {
                                 messaging_product: 'whatsapp',
                                 type: content_type,
                                 file: Faraday::Multipart::FilePart.new(file, content_type, filename)
                               })
    parsed_response = JSON.parse(response.body)
    return parsed_response['id'] if response.success? && parsed_response['id'].present?

    error = parsed_response['error'] || {}
    details = [error['code'], error['message']].compact.join(': ')
    raise CustomExceptions::WhatsappMediaUploadError, details.presence || I18n.t('errors.whatsapp.media_upload_failed')
  end

  def connection
    @connection ||= Faraday.new(headers: channel.api_headers.except('Content-Type')) do |faraday|
      faraday.request :multipart
      faraday.options.open_timeout = 10
      faraday.options.timeout = 60
    end
  end
end
