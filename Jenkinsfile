#!/usr/bin/env groovy

def gv

pipeline {

    stages {
        stage("init") {
            steps {
                script {
                    gv = load "script.groovy"
                }
            }
        }
        stage("deploy") {
            agent {
                label 'production'
            }
            steps {
                script {
                    gv.deployApp()
                }
            }
        }
    }
}
