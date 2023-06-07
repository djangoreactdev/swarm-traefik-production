

def deployApp() {
    echo 'deploying the application...'
    sh 'docker system prune -f'
    // sh 'docker pull djangoreactdev/portfolio:1.3'
    // sh 'docker pull djangoreactdev/portfolio-sanity:1.3'

    // cosmetic
    withCredentials([
            file(credentialsId: 'env_file_cosmetic_django', variable: 'ENV_cosmetic_django'),
            file(credentialsId: 'env_file_cosmetic_postgres', variable: 'ENV_cosmetic_postgres')
        ]) {
            writeFile file: 'cosmetic/.envs/.production/.django', text: readFile(ENV_cosmetic_django)
            writeFile file: 'cosmetic/.envs/.production/.postgres', text: readFile(ENV_cosmetic_postgres)
        }

    // codehelp
    withCredentials([
            file(credentialsId: 'env_file_codehelp_django', variable: 'ENV_codehelp_django'),
            file(credentialsId: 'env_file_codehelp_postgres', variable: 'ENV_codehelp_postgres')
        ]) {
            writeFile file: 'codehelp/.envs/.production/.django', text: readFile(ENV_codehelp_django)
            writeFile file: 'codehelp/.envs/.production/.postgres', text: readFile(ENV_codehelp_postgres)
        }

    withCredentials([usernamePassword(credentialsId: 'DockerHub', passwordVariable: 'PASSWORD', usernameVariable: 'USERNAME')]) {

        sh 'echo $PASSWORD | docker login -u $USERNAME --password-stdin'
        sh 'docker compose -f production-build.yml build --pull'
        // sh 'docker compose -f production-build.yml build'
    }

    // sh 'docker compose -f production-build.yml build --pull'
    sh 'docker stack rm production || true'
    // sh 'docker network rm production_default || true'
    // sh 'docker network create -d bridge production_default || true'
    sh 'docker network create -d bridge --scope=swarm --attachable production_bridge || true'
    sh 'docker stack deploy -c production.yml production'

} 

return this
