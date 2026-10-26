class LessonsController < ApplicationController
  before_action :set_course, only: %i[index create]
  before_action :set_lesson, only: %i[show update destroy]
  before_action :authorize_creator!, only: %i[create update destroy]

  # GET /courses/:course_id/lessons
  # Rascunhos só aparecem para o criador do curso.
  def index
    render json: @course.lessons.visible_to(current_user).order(:id)
  end

  # GET /lessons/:id
  def show
    render json: @lesson
  end

  # POST /courses/:course_id/lessons
  def create
    @lesson = @course.lessons.new(lesson_params)
    if @lesson.save
      render json: @lesson, status: :created
    else
      render json: { errors: @lesson.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /lessons/:id
  def update
    if @lesson.update(lesson_params)
      render json: @lesson
    else
      render json: { errors: @lesson.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /lessons/:id
  def destroy
    @lesson.destroy
    head :no_content
  end

  private

  def set_course
    @course = Course.find_by(id: params[:course_id])
    render json: { error: "Course not found" }, status: :not_found if @course.nil?
  end

  # A busca já aplica a regra de visibilidade: um rascunho de outro criador
  # responde 404 (e não 403), para não confirmar que a aula existe.
  def set_lesson
    @lesson = Lesson.visible_to(current_user).find_by(id: params[:id])
    render json: { error: "Lesson not found" }, status: :not_found if @lesson.nil?
  end

  def authorize_creator!
    course = @course || @lesson.course
    return if course.creator_id == current_user.id

    deny_access!(course)
  end

  def lesson_params
    params.require(:lesson).permit(:title, :status, :video_url)
  end
end
