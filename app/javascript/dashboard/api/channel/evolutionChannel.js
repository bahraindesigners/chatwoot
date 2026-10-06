/* global axios */
import ApiClient from '../ApiClient';

class EvolutionChannel extends ApiClient {
  constructor() {
    super('evolution', { accountScoped: true });
  }

  status(inboxId) {
    return axios.get(`${this.url}/${inboxId}/status`);
  }

  qr(inboxId) {
    return axios.post(`${this.url}/${inboxId}/qr`);
  }
}

export default new EvolutionChannel();
