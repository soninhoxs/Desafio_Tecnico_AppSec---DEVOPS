# db/seeds.rb — dados de DEMONSTRAÇÃO.
#
# Regras de segurança (VULN-04):
# - Em produção não roda, a menos que ALLOW_DEMO_SEED=true (ambiente de demo/lab).
# - Não existe senha padrão: em produção DEMO_USER_PASSWORD é obrigatória;
#   em dev/test, se não for informada, é gerada aleatoriamente e exibida no log.
# - Idempotente e não destrutivo: nunca apaga dados existentes
#   (a versão anterior começava com User.destroy_all).

if Rails.env.production? && ENV["ALLOW_DEMO_SEED"] != "true"
  puts "[seeds] Ignorado em produção. Defina ALLOW_DEMO_SEED=true apenas em ambiente de demonstração."
  return
end

demo_password = ENV["DEMO_USER_PASSWORD"].presence
if demo_password.nil?
  abort "[seeds] DEMO_USER_PASSWORD é obrigatória quando ALLOW_DEMO_SEED=true em produção." if Rails.env.production?

  demo_password = SecureRandom.base58(16)
  puts "[seeds] DEMO_USER_PASSWORD não definida; senha gerada para esta execução: #{demo_password}"
end

puts "--- Iniciando o Seed ---"

def demo_user(name:, email:, password:)
  User.find_or_create_by!(email: email) do |user|
    user.name = name
    user.password = password
  end
end

def demo_course(creator:, name:, description:, start_date:, end_date:, lessons:)
  course = Course.find_or_create_by!(name: name, creator: creator) do |c|
    c.description = description
    c.start_date = start_date
    c.end_date = end_date
  end
  lessons.each do |attrs|
    course.lessons.find_or_create_by!(title: attrs[:title]) do |lesson|
      lesson.status = attrs[:status]
      lesson.video_url = attrs[:video_url]
    end
  end
  course
end

instrutor_tech = demo_user(name: "Instrutor Tech", email: "tech@coursesphere.com", password: demo_password)
instrutor_design = demo_user(name: "Instrutor Design", email: "design@coursesphere.com", password: demo_password)

demo_course(
  creator: instrutor_tech,
  name: "Node.js: Do Zero ao Microserviço",
  description: "Aprenda a construir arquiteturas escaláveis com Node.js, Express e Docker. Um guia completo para o desenvolvimento backend moderno.",
  start_date: Date.today - 10.days, end_date: Date.today + 50.days,
  lessons: [
    { title: "Introdução à Arquitetura Backend", status: "published", video_url: "https://www.youtube.com" },
    { title: "Configurando o Ambiente Local", status: "published", video_url: "https://www.youtube.com" },
    { title: "Criando a primeira API Rest", status: "published", video_url: "https://www.youtube.com" },
    { title: "Tratamento de Erros Avançado", status: "draft" }
  ]
)

demo_course(
  creator: instrutor_design,
  name: "Fundamentos de UI/UX Design",
  description: "Domine o Figma e entenda os princípios da experiência do usuário para criar interfaces bonitas e funcionais.",
  start_date: Date.today + 5.days, end_date: Date.today + 35.days,
  lessons: [
    { title: "Os 10 Princípios da Heurística de Nielsen", status: "published", video_url: "https://www.youtube.com" },
    { title: "Tipografia e Cores: O Guia Definitivo", status: "published", video_url: "https://www.youtube.com" },
    { title: "Desenhando seu primeiro Wireframe no Figma", status: "draft" }
  ]
)

demo_course(
  creator: instrutor_tech,
  name: "Python para Data Science",
  description: "Explore o mundo da análise de dados utilizando Pandas, NumPy e ferramentas de Machine Learning com Python.",
  start_date: Date.today, end_date: Date.today + 90.days,
  lessons: [
    { title: "Configurando o Jupyter Notebook", status: "published", video_url: "https://www.youtube.com" },
    { title: "Lendo Dados de CSV com Pandas", status: "published", video_url: "https://www.youtube.com" },
    { title: "Limpando e Tratando Valores Nulos", status: "published" },
    { title: "Criando Gráficos com Matplotlib", status: "draft" }
  ]
)

demo_course(
  creator: instrutor_design,
  name: "Marketing Digital Estratégico",
  description: "Aprenda a criar campanhas de conversão que geram resultados consistentes utilizando tráfego pago e orgânico.",
  start_date: Date.today + 15.days, end_date: Date.today + 45.days,
  lessons: [
    { title: "Como definir o seu Público-Alvo", status: "published" },
    { title: "Tráfego Orgânico vs Pago", status: "draft" }
  ]
)

puts "--- Seed finalizado: usuários tech@coursesphere.com e design@coursesphere.com (senha = DEMO_USER_PASSWORD) ---"
