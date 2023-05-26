#!/usr/bin/env groovy

def gv

pipeline {
    agent {
        label 'production'
    }

    stages {
        stage("init") {
            steps {
                script {
                    gv = load "script.groovy"
                }
            }
        }
        stage("deploy") {

            steps {
                script {
                    gv.deployApp()
                }
            }
        }
    }
}
