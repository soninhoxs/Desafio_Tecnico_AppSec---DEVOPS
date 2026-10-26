class CoursesController < ApplicationController
  before_action :authorize_request 
  before_action :set_course, only: [:show, :update, :destroy]
  before_action :authorize_creator!, only: [:update, :destroy]

  def index
    @courses = Course.all
    render json: @courses
  end

  def show
    render json: @course
  end

  def create
    @course = current_user.created_courses.new(course_params)
    if @course.save
      render json: @course, status: :created
    else
      render json: { errors: @course.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @course.update(course_params)
      render json: @course
    else
      render json: { errors: @course.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @course.destroy
    head :no_content
  end

  private

  def set_course
    @course = Course.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Course not found' }, status: :not_found
  end

  def authorize_creator!
    deny_access!(@course) unless @course.creator_id == current_user.id
  end

  def course_params
    params.require(:course).permit(:name, :description, :start_date, :end_date)
  end
end