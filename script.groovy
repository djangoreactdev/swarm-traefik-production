

def deployApp() {
    echo 'deploying the application...'
    sh 'pwd && ls'
    sh 'docker compose -f production-build.yml build'
    sh 'docker stack rm production || true'
    sh 'docker network create production_default'
    sh 'docker stack deploy -c production.yml production'
} 

return this
