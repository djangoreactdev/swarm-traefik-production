

def deployApp() {
    echo 'deploying the application...'
    sh 'docker compose -f production.yml build'
    sh 'docker stack rm production || true'
    sh 'docker stack deploy -c production.yml production'
} 

return this
