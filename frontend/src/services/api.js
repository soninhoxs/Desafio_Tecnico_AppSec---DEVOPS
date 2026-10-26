import axios from 'axios';

const api = axios.create({
  // Mesma origem por padrão: o balanceador (ou o proxy do Vite em dev) envia /api para a API.
  baseURL: import.meta.env.VITE_API_URL || '/api',
});

// Adiciona o token ao cabeçalho de todas as requisições, se ele existir
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

export default api;