

def deployApp() {
    echo 'deploying the application...'
    sh 'docker system prune -f'
    sh 'docker pull djangoreactdev/portfolio:1.3'
    sh 'docker pull djangoreactdev/portfolio-sanity:1.3'
    sh 'docker compose -f production-build.yml build --pull'
    sh 'docker stack rm production || true'
    // sh 'docker network rm production_default || true'
    // sh 'docker network rm production_default || true'
    sh 'docker network create -d bridge production_default || true'
    sh 'docker network create -d overlay --scope=swarm --attachable production_default || true'
    sh 'docker stack deploy -c production.yml production'
} 

return this
