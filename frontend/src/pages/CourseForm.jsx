import { useState, useEffect } from 'react';
import { useNavigate, useParams, Link } from 'react-router-dom';
import api from '../services/api';

export function CourseForm() {
  const { id } = useParams();
  const navigate = useNavigate();
  const isEditing = Boolean(id);

  const [formData, setFormData] = useState({
    name: '',
    description: '',
    start_date: '',
    end_date: ''
  });
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(isEditing);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (isEditing) {
      api.get(`/courses/${id}`)
        .then(res => {
          setFormData({
            name: res.data.name,
            description: res.data.description || '',
            start_date: res.data.start_date,
            end_date: res.data.end_date
          });
        })
        .catch(() => setError("Erro ao carregar os detalhes do curso."))
        .finally(() => setLoading(false));
    }
  }, [id, isEditing]);

  const handleChange = (e) => {
    setFormData({ ...formData, [e.target.name]: e.target.value });
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError(null);
    setSaving(true);
    
    try {
      if (isEditing) {
        await api.put(`/courses/${id}`, { course: formData });
        navigate(`/courses/${id}`);
      } else {
        const res = await api.post('/courses', { course: formData });
        navigate(`/courses/${res.data.id}`);
      }
    } catch (err) {
      if (err.response?.data?.errors) {
        setError(err.response.data.errors.join(', '));
      } else {
        setError("Erro ao salvar curso. Verifique as datas e tente novamente.");
      }
    } finally {
      setSaving(false);
    }
  };

  if (loading) return <div className="loading"><div className="spinner"></div><p>Carregando...</p></div>;

  return (
    <div className="dashboard-container">

      <div className="auth-card" style={{ maxWidth: '600px', margin: '0 auto', animation: 'none' }}>
        <h2 style={{fontSize: '1.8rem', textAlign: 'left', marginBottom: '2rem'}}>
          {isEditing ? "Editar Curso" : "Criar Novo Curso"}
        </h2>

        {error && (
          <div className="error-box">
            <p className="error-message">{error}</p>
          </div>
        )}

        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label>Nome do Curso *</label>
            <input 
              type="text" 
              name="name" 
              value={formData.name} 
              onChange={handleChange} 
              placeholder="Mínimo 3 caracteres"
              required 
              minLength="3"
              spellCheck="false"
            />
          </div>
          
          <div className="form-group">
            <label>Descrição</label>
            <input 
              type="text" 
              name="description" 
              value={formData.description} 
              onChange={handleChange} 
              placeholder="Sobre o que é este curso?"
              spellCheck="false"
            />
          </div>

          <div style={{display: 'flex', gap: '1rem'}}>
            <div className="form-group" style={{flex: 1}}>
              <label>Data de Início *</label>
              <input 
                type="date" 
                name="start_date" 
                value={formData.start_date} 
                onChange={handleChange} 
                required 
              />
            </div>

            <div className="form-group" style={{flex: 1}}>
              <label>Data de Término *</label>
              <input 
                type="date" 
                name="end_date" 
                value={formData.end_date} 
                onChange={handleChange} 
                required 
              />
            </div>
          </div>

          <div style={{display: 'flex', gap: '1rem', marginTop: '1rem'}}>
            <button type="submit" disabled={saving} style={{flex: 2, marginTop: 0}}>
              {saving ? "Salvando..." : (isEditing ? "Salvar Alterações" : "Criar Curso")}
            </button>
            <Link to={isEditing ? `/courses/${id}` : "/dashboard"} className="btn-secondary" style={{flex: 1, textDecoration: 'none'}}>
              Cancelar
            </Link>
          </div>
        </form>
      </div>
    </div>
  );
}
