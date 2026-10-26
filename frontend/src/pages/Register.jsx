import { useState, useContext } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { AuthContext } from '../contexts/AuthContext';

export function Register() {
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    password: '',
    password_confirmation: ''
  });
  const [errors, setErrors] = useState([]);
  const [showPassword, setShowPassword] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  
  const { register } = useContext(AuthContext);
  const navigate = useNavigate();

  function handleChange(e) {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setErrors([]);

    if (formData.password !== formData.password_confirmation) {
      setErrors(['As senhas não coincidem.']);
      return;
    }

    setSubmitting(true);
    try {
      await register(
        formData.name, 
        formData.email, 
        formData.password, 
        formData.password_confirmation
      );
      navigate('/dashboard');
    } catch (err) {
      const backendErrors = err.response?.data?.errors;
      setErrors(backendErrors || ['Erro ao criar conta.']);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="auth-container">
      <div className="auth-card">
        <div className="auth-logo">
          <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"></path><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"></path></svg>
          <span>CourseSphere</span>
        </div>
        <h2>Criar conta</h2>

        {errors.length > 0 && (
          <div className="error-box">
            {errors.map((err, i) => (
              <p key={i} className="error-message">• {err}</p>
            ))}
          </div>
        )}

        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label>Nome Completo</label>
            <input 
              name="name"
              type="text" 
              required 
              placeholder="Seu nome completo"
              value={formData.name}
              onChange={handleChange}
              spellCheck="false"
            />
          </div>

          <div className="form-group">
            <label>E-mail</label>
            <input 
              name="email"
              type="email" 
              required 
              placeholder="seu@email.com"
              value={formData.email}
              onChange={handleChange}
              spellCheck="false"
            />
          </div>

          <div className="form-group">
            <label>Senha</label>
            <div className="password-wrapper">
              <input 
                name="password"
                type={showPassword ? 'text' : 'password'}
                required 
                placeholder="••••••••"
                minLength="12"
                value={formData.password}
                onChange={handleChange}
                spellCheck="false"
              />
              <button type="button" className="password-toggle" onClick={() => setShowPassword(!showPassword)} tabIndex={-1}>
                {showPassword ? (
                  <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94"></path><path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19"></path><line x1="1" y1="1" x2="23" y2="23"></line></svg>
                ) : (
                  <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle></svg>
                )}
              </button>
            </div>
            <p className="field-hint">Mínimo de 12 caracteres. Prefira uma frase longa; senhas comuns são recusadas.</p>
          </div>

          <div className="form-group">
            <label>Confirmar Senha</label>
            <div className="password-wrapper">
              <input 
                name="password_confirmation"
                type={showPassword ? 'text' : 'password'}
                required 
                placeholder="••••••••"
                value={formData.password_confirmation}
                onChange={handleChange}
                spellCheck="false"
              />
            </div>
          </div>

          <button type="submit" disabled={submitting}>
            {submitting ? (
              <><span className="btn-spinner"></span> Criando conta...</>
            ) : 'Registrar'}
          </button>
        </form>

        <p className="auth-footer">
          Já tem conta? <Link to="/login">Entrar agora</Link>
        </p>
      </div>
    </div>
  );
}