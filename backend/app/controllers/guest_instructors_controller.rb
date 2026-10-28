# GET /courses/:course_id/guest_instructor
#
# Card do "instrutor convidado" na página do curso. A busca na API externa
# (randomuser.me) é feita pelo GuestInstructorClient, com timeout, retry,
# circuit breaker e cache. Responde sempre 200 quando o curso existe: se a
# dependência externa falhar, volta `available: false` e a página do curso
# continua funcionando sem o card (degradação controlada, não erro 5xx).
class GuestInstructorsController < ApplicationController
  before_action :set_course

  def show
    result = GuestInstructorClient.instance.fetch(@course.id)
    render json: { available: result.available?, instructor: result.instructor }
  end

  private

  def set_course
    @course = Course.find_by(id: params[:course_id])
    render json: { error: "Course not found" }, status: :not_found if @course.nil?
  end
end
