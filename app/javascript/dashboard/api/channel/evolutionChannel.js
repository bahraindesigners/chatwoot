/* global axios */
import ApiClient from '../ApiClient';

class EvolutionChannel extends ApiClient {
  constructor() {
    super('evolution', { accountScoped: true });
  }

  status(inboxId, config) {
    return axios.get(`${this.url}/${inboxId}/status`, config);
  }

  qr(inboxId, config) {
    return axios.post(`${this.url}/${inboxId}/qr`, {}, config);
  }
}

export default new EvolutionChannel();
