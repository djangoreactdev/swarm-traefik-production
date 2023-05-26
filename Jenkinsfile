#!/usr/bin/env groovy

def gv

pipeline {
    agent {
        label 'developer'
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
