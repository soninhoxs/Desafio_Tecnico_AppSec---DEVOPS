import { useEffect, useState, useContext } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { AuthContext } from '../contexts/auth-context';
import api from '../services/api';
import { CourseCard } from '../components/CourseCard';

const COURSES_PER_PAGE = 6;

export function Dashboard() {
  const [courses, setCourses] = useState([]);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [currentPage, setCurrentPage] = useState(1);
  
  const { logout } = useContext(AuthContext);
  const navigate = useNavigate();

  function handleLogout() {
    logout();
    navigate('/login');
  }

  useEffect(() => {
    api.get('/courses')
      .then(res => setCourses(res.data))
      .catch(err => console.error("Erro ao buscar cursos", err))
      .finally(() => setLoading(false));
  }, []);

  const filteredCourses = courses.filter(c =>
    c.name.toLowerCase().includes(search.toLowerCase())
  );

  // Reseta para a primeira página sempre que a busca mudar
  function handleSearch(value) {
    setSearch(value);
    setCurrentPage(1);
  }

  const totalPages = Math.ceil(filteredCourses.length / COURSES_PER_PAGE);
  const paginatedCourses = filteredCourses.slice(
    (currentPage - 1) * COURSES_PER_PAGE,
    currentPage * COURSES_PER_PAGE
  );

  if (loading) return (
    <div className="dashboard-container">
      <div className="loading">
        <div className="spinner"></div>
        <p>Carregando seu universo de conhecimento...</p>
      </div>
    </div>
  );

  return (
    <div className="dashboard-container">
      <nav className="top-nav" style={{ marginBottom: '2rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div className="brand-logo" style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', color: 'var(--primary-color)', fontWeight: '700', fontSize: '1.25rem' }}>
          <svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"></path><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"></path></svg>
          CourseSphere
        </div>
        <button onClick={handleLogout} className="logout-btn">
          Sair
        </button>
      </nav>

      <header className="dash-header">
        <div className="header-titles">
          <h1>Cursos</h1>
        </div>
        <div className="header-actions" style={{ flex: 1, justifyContent: 'flex-end', width: '100%' }}>
          <div className="search-wrapper">
            <svg className="search-icon" xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line></svg>
            <input
              type="text"
              placeholder="Pesquisar por nome do curso..."
              value={search}
              onChange={(e) => handleSearch(e.target.value)}
              className="search-input"
              spellCheck="false"
            />
          </div>
          <div style={{ display: 'flex', gap: '1rem', alignItems: 'center' }}>
            <Link to="/courses/new" className="btn-primary" style={{textDecoration: 'none'}}>
              <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="5" x2="12" y2="19"></line><line x1="5" y1="12" x2="19" y2="12"></line></svg>
              Criar Curso
            </Link>
          </div>
        </div>
      </header>

      <section className="courses-section">
        {courses.length === 0 ? (
          <div className="empty-state">
            <div className="empty-icon">🚀</div>
            <h3>Nenhum curso ainda</h3>
            <p>Você ainda não tem cursos. Que tal criar o seu primeiro agora?</p>
            <Link to="/courses/new" className="btn-primary" style={{textDecoration: 'none', marginTop: '1.5rem', display: 'inline-flex'}}>
              <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="5" x2="12" y2="19"></line><line x1="5" y1="12" x2="19" y2="12"></line></svg>
              Criar meu primeiro curso
            </Link>
          </div>
        ) : filteredCourses.length > 0 ? (
          <>
            <div className="courses-grid">
              {paginatedCourses.map(course => (
                <CourseCard key={course.id} course={course} />
              ))}
            </div>

            {totalPages > 1 && (
              <div className="pagination">
                <button
                  className="pagination-btn"
                  onClick={() => setCurrentPage(p => p - 1)}
                  disabled={currentPage === 1}
                  aria-label="Página anterior"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="15 18 9 12 15 6"/></svg>
                </button>

                {Array.from({ length: totalPages }, (_, i) => i + 1).map(page => (
                  <button
                    key={page}
                    className={`pagination-btn ${currentPage === page ? 'active' : ''}`}
                    onClick={() => setCurrentPage(page)}
                    aria-label={`Página ${page}`}
                    aria-current={currentPage === page ? 'page' : undefined}
                  >
                    {page}
                  </button>
                ))}

                <button
                  className="pagination-btn"
                  onClick={() => setCurrentPage(p => p + 1)}
                  disabled={currentPage === totalPages}
                  aria-label="Próxima página"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="9 18 15 12 9 6"/></svg>
                </button>

                <span className="pagination-info">
                  {(currentPage - 1) * COURSES_PER_PAGE + 1}–{Math.min(currentPage * COURSES_PER_PAGE, filteredCourses.length)} de {filteredCourses.length}
                </span>
              </div>
            )}
          </>
        ) : (
          <div className="empty-state">
            <div className="empty-icon">🔍</div>
            <h3>Nenhum curso encontrado</h3>
            <p>Não encontramos cursos correspondentes à sua busca: "<strong>{search}</strong>".</p>
            <button onClick={() => handleSearch('')} className="btn-secondary" style={{marginTop: '1.5rem'}}>Limpar Busca</button>
          </div>
        )}
      </section>
    </div>
  );
}
