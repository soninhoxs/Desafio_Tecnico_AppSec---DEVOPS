import { useState, useEffect } from 'react';
import { useNavigate, useParams, Link } from 'react-router-dom';
import api from '../services/api';

export function LessonForm() {
  const { id, lessonId } = useParams(); // id do curso, lessonId se for edição
  const navigate = useNavigate();
  const isEditing = Boolean(lessonId);

  const [formData, setFormData] = useState({
    title: '',
    status: 'draft',
    video_url: ''
  });
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(isEditing);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (isEditing) {
      api.get(`/lessons/${lessonId}`)
        .then(res => {
          setFormData({
            title: res.data.title,
            status: res.data.status,
            video_url: res.data.video_url || ''
          });
        })
        .catch(() => setError("Erro ao carregar os detalhes da aula."))
        .finally(() => setLoading(false));
    }
  }, [lessonId, isEditing]);

  const handleChange = (e) => {
    setFormData({ ...formData, [e.target.name]: e.target.value });
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError(null);

    let videoUrl = formData.video_url;

    if (videoUrl && videoUrl.trim() !== '') {
      videoUrl = videoUrl.trim();
      if (!/^https?:\/\//i.test(videoUrl)) {
        videoUrl = `https://${videoUrl}`;
      }

      try {
        const parsedUrl = new URL(videoUrl);
        if (parsedUrl.protocol !== 'http:' && parsedUrl.protocol !== 'https:') {
          setError("A URL do vídeo deve começar com http:// ou https://");
          return;
        }
        if (!parsedUrl.hostname.includes('.')) {
          setError("A URL deve conter um domínio válido (ex: youtube.com).");
          return;
        }
      } catch {
        setError("Por favor, insira uma URL válida para o vídeo.");
        return;
      }
    }

    setSaving(true);

    const payload = { ...formData, video_url: videoUrl };

    try {
      if (isEditing) {
        await api.put(`/lessons/${lessonId}`, { lesson: payload });
      } else {
        await api.post(`/courses/${id}/lessons`, { lesson: payload });
      }
      navigate(`/courses/${id}`);
    } catch (err) {
      if (err.response?.data?.errors) {
        setError(err.response.data.errors.join(', '));
      } else {
        setError("Erro ao salvar aula. Verifique a URL do vídeo e tente novamente.");
      }
    } finally {
      setSaving(false);
    }
  };

  if (loading) return <div className="loading"><div className="spinner"></div><p>Carregando...</p></div>;

  return (
    <div className="dashboard-container">

      <div className="auth-card" style={{ maxWidth: '600px', margin: '0 auto', animation: 'none' }}>
        <h2 style={{ fontSize: '1.8rem', textAlign: 'left', marginBottom: '2rem' }}>
          {isEditing ? "Editar Aula" : "Adicionar Nova Aula"}
        </h2>

        {error && (
          <div className="error-box">
            <p className="error-message">{error}</p>
          </div>
        )}

        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label>Título da Aula *</label>
            <input
              type="text"
              name="title"
              value={formData.title}
              onChange={handleChange}
              placeholder="Ex: Introdução ao React"
              required
              minLength="3"
              spellCheck="false"
            />
          </div>

          <div className="form-group">
            <label>URL do Vídeo</label>
            <input
              type="text"
              name="video_url"
              value={formData.video_url}
              onChange={handleChange}
              placeholder="Ex: youtube.com/..."
              spellCheck="false"
            />
          </div>

          <div className="form-group">
            <label>Status</label>
            <select
              name="status"
              value={formData.status}
              onChange={handleChange}
              className="form-select"
            >
              <option value="draft">Rascunho</option>
              <option value="published">Publicada</option>
            </select>
          </div>

          <div style={{ display: 'flex', gap: '1rem', marginTop: '1rem' }}>
            <button type="submit" disabled={saving} style={{ flex: 2, marginTop: 0 }}>
              {saving ? "Salvando..." : (isEditing ? "Salvar Alterações" : "Adicionar Aula")}
            </button>
            <Link to={`/courses/${id}`} className="btn-secondary" style={{ flex: 1, textDecoration: 'none' }}>
              Cancelar
            </Link>
          </div>
        </form>
      </div>
    </div>
  );
}
