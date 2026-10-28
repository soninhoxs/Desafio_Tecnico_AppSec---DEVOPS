import { useEffect, useState, useContext } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { AuthContext } from '../contexts/auth-context';
import api from '../services/api';
import { ConfirmModal } from '../components/ConfirmModal';

// Defesa em profundidade: o backend já só aceita http/https, mas o link só é
// renderizado como <a href> se o protocolo for seguro (dados antigos/outros clientes).
function isSafeHttpUrl(value) {
  if (!value) return false;
  try {
    const { protocol } = new URL(value);
    return protocol === 'http:' || protocol === 'https:';
  } catch {
    return false;
  }
}

export function CourseDetails() {
  const { id } = useParams();
  const [course, setCourse] = useState(null);
  const [lessons, setLessons] = useState([]);
  const [statusFilter, setStatusFilter] = useState('all');
  const [instructor, setInstructor] = useState(null);
  const [instructorUnavailable, setInstructorUnavailable] = useState(false);
  const [error, setError] = useState(null);
  const [lessonsError, setLessonsError] = useState(null);
  const [expandedLesson, setExpandedLesson] = useState(null);

  // Estado do modal de confirmação
  const [modal, setModal] = useState({ isOpen: false, title: '', message: '', onConfirm: null });

  const { logout, user } = useContext(AuthContext);
  const navigate = useNavigate();

  const isCreator = course && user && course.creator_id === user.id;

  function handleLogout() {
    logout();
    navigate('/login');
  }

  function openModal({ title, message, onConfirm }) {
    setModal({ isOpen: true, title, message, onConfirm });
  }

  function closeModal() {
    setModal({ isOpen: false, title: '', message: '', onConfirm: null });
  }

  const handleDeleteCourse = () => {
    openModal({
      title: 'Excluir Curso',
      message: 'Tem certeza que deseja excluir este curso? Todas as aulas serão removidas e essa ação não pode ser desfeita.',
      onConfirm: async () => {
        closeModal();
        try {
          await api.delete(`/courses/${id}`);
          navigate('/dashboard');
        } catch {
          setError('Erro ao excluir curso. Tente novamente.');
        }
      },
    });
  };

  const handleDeleteLesson = (lessonId, lessonTitle) => {
    openModal({
      title: 'Excluir Aula',
      message: `Deseja excluir a aula "${lessonTitle}"? Esta ação não pode ser desfeita.`,
      onConfirm: async () => {
        closeModal();
        try {
          await api.delete(`/lessons/${lessonId}`);
          setLessons(prev => prev.filter(l => l.id !== lessonId));
        } catch {
          setLessonsError('Erro ao excluir aula. Tente novamente.');
        }
      },
    });
  };

  useEffect(() => {
    // 1. Dados do curso e aulas do seu backend
    api.get(`/courses/${id}`)
      .then(res => setCourse(res.data))
      .catch(() => setError("Não foi possível carregar os detalhes deste curso."));
      
    api.get(`/courses/${id}/lessons`)
      .then(res => setLessons(res.data))
      .catch(err => {
        console.error("Lessons error:", err);
        setLessonsError("Ainda não conseguimos listar as aulas para este curso.");
      });

    // 2. Instrutor convidado (API externa randomuser.me). A busca passa pela
    // API do CourseSphere, que aplica timeout, retry, circuit breaker e cache.
    // Se a dependência estiver fora do ar, vem available: false e a página
    // continua funcionando, só sem o card (degradação controlada).
    api.get(`/courses/${id}/guest_instructor`)
      .then(res => {
        if (res.data.available) setInstructor(res.data.instructor);
        else setInstructorUnavailable(true);
      })
      .catch(() => setInstructorUnavailable(true));
  }, [id]);

  if (error) return (
    <div className="details-container">
      <div className="empty-state error-state">
        <div className="empty-icon">⚠️</div>
        <h3>Ops! Alguma coisa deu errado.</h3>
        <p>{error}</p>
        <Link to="/dashboard" className="btn-primary" style={{ display: 'inline-block', marginTop: '1rem', textDecoration: 'none' }}>Voltar ao Dashboard</Link>
      </div>
    </div>
  );

  if (!course) return (
    <div className="details-container">
      <div className="loading">
        <div className="spinner"></div>
        <p>Preparando a sala de aula...</p>
      </div>
    </div>
  );

  return (
    <div className="details-container">
      {/* Modal de confirmação */}
      <ConfirmModal
        isOpen={modal.isOpen}
        title={modal.title}
        message={modal.message}
        onConfirm={modal.onConfirm}
        onCancel={closeModal}
        danger
      />

      <nav className="top-nav" style={{ marginBottom: '2rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '2rem' }}>
          <div className="brand-logo" style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', color: 'var(--primary-color)', fontWeight: '700', fontSize: '1.25rem' }}>
            <svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"></path><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"></path></svg>
            CourseSphere
          </div>
          <Link to="/dashboard" className="btn-secondary" style={{ textDecoration: 'none', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="19" y1="12" x2="5" y2="12"></line><polyline points="12 19 5 12 12 5"></polyline></svg>
            Voltar
          </Link>
        </div>
        <button onClick={handleLogout} className="logout-btn">
          Sair
        </button>
      </nav>
      
      <header className="course-hero">
        <div className="course-hero-content">
          <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center'}}>
            <span className="course-badge">Curso Completo</span>
            {isCreator && (
              <div style={{display: 'flex', gap: '0.5rem'}}>
                <Link to={`/courses/${id}/edit`} className="btn-secondary" style={{textDecoration: 'none'}}>
                  Editar
                </Link>
                <button onClick={handleDeleteCourse} className="btn-secondary" style={{borderColor: 'var(--error-color)', color: 'var(--error-color)'}}>
                  Excluir
                </button>
              </div>
            )}
          </div>
          <h1 className="course-title">{course.name}</h1>
          <p className="course-description">{course.description || "Este curso não possui uma descrição detalhada ainda."}</p>
          <div className="course-meta">
            <div className="meta-item">
              <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect><line x1="16" y1="2" x2="16" y2="6"></line><line x1="8" y1="2" x2="8" y2="6"></line><line x1="3" y1="10" x2="21" y2="10"></line></svg>
              <span>Início: <strong>{new Date(course.start_date).toLocaleDateString('pt-BR')}</strong></span>
            </div>
            <div className="meta-item">
              <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect><line x1="16" y1="2" x2="16" y2="6"></line><line x1="8" y1="2" x2="8" y2="6"></line><line x1="3" y1="10" x2="21" y2="10"></line></svg>
              <span>Término: <strong>{new Date(course.end_date).toLocaleDateString('pt-BR')}</strong></span>
            </div>
            <div className="meta-item">
              <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"></circle><polyline points="12 6 12 12 16 14"></polyline></svg>
              <span>Total de Aulas: <strong>{lessons.length}</strong></span>
            </div>
          </div>
        </div>
      </header>

      <div className="details-layout">
        <main className="lessons-section">
          <div className="section-header" style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '2rem'}}>
            <div>
              <h2 style={{marginBottom: '0'}}>Aulas</h2>
            </div>
            {isCreator && (
              <Link to={`/courses/${id}/lessons/new`} className="btn-primary" style={{textDecoration: 'none'}}>
                + Nova Aula
              </Link>
            )}
          </div>

          <div className="filter-bar">
            {['all', 'published', 'draft'].map(f => (
              <button
                key={f}
                onClick={() => setStatusFilter(f)}
                className={`filter-btn ${statusFilter === f ? 'active' : ''}`}
              >
                {f === 'all' ? 'Todas' : f === 'published' ? 'Publicadas' : 'Rascunhos'}
              </button>
            ))}
            <span className="filter-count">
              {lessons.filter(l => statusFilter === 'all' || l.status === statusFilter).length} aula(s)
            </span>
          </div>

          {lessonsError && (
            <div className="alert alert-warning" style={{marginBottom: '1.5rem', padding: '1rem', backgroundColor: 'var(--error-bg)', color: 'var(--error-color)', borderRadius: 'var(--radius-md)'}}>
              {lessonsError}
            </div>
          )}

          <div className="lessons-list">
            {(() => {
              const filtered = lessons.filter(l => statusFilter === 'all' || l.status === statusFilter);
              if (filtered.length === 0 && !lessonsError) return (
                <div className="empty-state">
                  <div className="empty-icon">📚</div>
                  <h3>{statusFilter === 'all' ? 'Nenhuma aula disponível' : `Nenhuma aula ${statusFilter === 'published' ? 'publicada' : 'em rascunho'}`}</h3>
                  <p>{statusFilter === 'all' ? 'Este curso ainda não possui aulas cadastradas pelo instrutor.' : 'Tente outro filtro.'}</p>
                </div>
              );
              return filtered.map((lesson, index) => (
                <div key={lesson.id} className="lesson-item" style={{ flexDirection: 'column', alignItems: 'stretch', gap: '1rem', cursor: 'pointer' }} onClick={() => setExpandedLesson(expandedLesson === lesson.id ? null : lesson.id)}>
                  <div style={{ display: 'flex', width: '100%', alignItems: 'center', gap: '1.5rem' }}>
                    <div className="lesson-icon">
                      {lesson.status === 'published' ? (
                        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"></circle><polygon points="10 8 16 12 10 16 10 8"></polygon></svg>
                      ) : (
                        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"></rect><path d="M7 11V7a5 5 0 0 1 10 0v4"></path></svg>
                      )}
                    </div>
                    <div className="lesson-details">
                      <span className="lesson-number">Aula {index + 1}</span>
                      <h4 className="lesson-title">{lesson.title}</h4>
                    </div>
                    <div className="lesson-status" style={{display: 'flex', alignItems: 'center', gap: '1rem'}}>
                      <span className={`status-badge ${lesson.status}`}>
                        {lesson.status === 'published' ? 'Publicada' : 'Rascunho'}
                      </span>
                      {isCreator && (
                        <div style={{display: 'flex', gap: '0.25rem'}}>
                          <Link
                            to={`/courses/${id}/lessons/${lesson.id}/edit`}
                            className="logout-link"
                            style={{padding: '0.25rem 0.5rem', background: 'transparent', color: 'var(--text-secondary)'}}
                            title="Editar Aula"
                            onClick={(e) => e.stopPropagation()}
                          >
                            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 20h9"></path><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"></path></svg>
                          </Link>
                          <button
                            onClick={(e) => { e.stopPropagation(); handleDeleteLesson(lesson.id, lesson.title); }}
                            className="logout-link"
                            style={{padding: '0.25rem 0.5rem', background: 'transparent'}}
                            title="Excluir Aula"
                          >
                            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path></svg>
                          </button>
                        </div>
                      )}
                    </div>
                  </div>
                  
                  {expandedLesson === lesson.id && (
                    <div style={{ padding: '1rem', background: 'rgba(0,0,0,0.2)', borderRadius: 'var(--radius-md)', borderLeft: '4px solid var(--primary-color)' }}>
                      <p style={{ margin: 0, color: 'var(--text-secondary)', fontSize: '0.85rem', marginBottom: '0.25rem' }}>Link da Aula:</p>
                      {isSafeHttpUrl(lesson.video_url) ? (
                        <a href={lesson.video_url} target="_blank" rel="noopener noreferrer" style={{ color: 'var(--primary-hover)', wordBreak: 'break-all', textDecoration: 'none', fontWeight: '500' }} onClick={(e) => e.stopPropagation()}>
                          {lesson.video_url}
                        </a>
                      ) : (
                        <span style={{ color: 'var(--text-secondary)' }}>Nenhuma URL informada para esta aula.</span>
                      )}
                    </div>
                  )}
                </div>
              ));
            })()}
          </div>
        </main>

        <aside className="sidebar">
          <div className="instructor-widget">
            <h3 className="widget-title">Instrutor Convidado</h3>
            {instructor ? (
              <div className="instructor-profile">
                <div className="avatar-container">
                  {instructor.picture_url && (
                    <img src={instructor.picture_url} alt="Foto do Instrutor" className="instructor-avatar" />
                  )}
                  <div className="online-indicator"></div>
                </div>
                <h4 className="instructor-name">{instructor.name}</h4>
                <p className="instructor-email">{instructor.email}</p>
                <div className="instructor-bio">
                  <p>Especialista com anos de experiência no mercado, preparado para guiar você ao longo deste curso.</p>
                </div>
              </div>
            ) : instructorUnavailable ? (
              <p style={{textAlign: 'center', color: 'var(--text-secondary)'}}>
                Instrutor convidado indisponível no momento.
              </p>
            ) : (
              <div className="loading-instructor">
                <div className="spinner" style={{width: '30px', height: '30px', margin: '0 auto 1rem'}}></div>
                <p style={{textAlign: 'center', color: 'var(--text-secondary)'}}>Carregando perfil...</p>
              </div>
            )}
          </div>
        </aside>
      </div>
    </div>
  );
}