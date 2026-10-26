import { Routes, Route, Navigate } from 'react-router-dom';
import { useContext } from 'react';
import { AuthContext } from '../contexts/auth-context';

import { Login } from '../pages/Login';
import { Register } from '../pages/Register';
import { Dashboard } from '../pages/Dashboard';
import { CourseDetails } from '../pages/CourseDetails';
import { CourseForm } from '../pages/CourseForm';
import { LessonForm } from '../pages/LessonForm';

export default function AppRoutes() {
  const { signed, loading } = useContext(AuthContext);

  if (loading) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100vh' }}>
        <div className="spinner"></div>
      </div>
    );
  }

  return (
    <Routes>
      <Route path="/login" element={!signed ? <Login /> : <Navigate to="/dashboard" />} />
      <Route path="/register" element={!signed ? <Register /> : <Navigate to="/dashboard" />} />

      <Route path="/dashboard" element={signed ? <Dashboard /> : <Navigate to="/login" />} />
      <Route path="/courses/new" element={signed ? <CourseForm /> : <Navigate to="/login" />} />
      <Route path="/courses/:id" element={signed ? <CourseDetails /> : <Navigate to="/login" />} />
      <Route path="/courses/:id/edit" element={signed ? <CourseForm /> : <Navigate to="/login" />} />
      <Route path="/courses/:id/lessons/new" element={signed ? <LessonForm /> : <Navigate to="/login" />} />
      <Route path="/courses/:id/lessons/:lessonId/edit" element={signed ? <LessonForm /> : <Navigate to="/login" />} />
      
      <Route path="*" element={<Navigate to={signed ? "/dashboard" : "/login"} />} />
    </Routes>
  );
}