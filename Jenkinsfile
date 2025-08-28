pipeline {
    agent any
    environment {
        DOCKER_IMAGE = "saravanave/trend-react-app"
        DOCKERHUB_CREDENTIALS = "dockerhub_credentials"
        // Update the path to the new location
        KUBECONFIG_PATH = "/var/lib/jenkins/.kube/config" 
    }
    stages {
        stage('Git Checkout') {
            steps {
                // This is handled automatically by the Git plugin
                echo 'Checking out code from Git...'
                checkout scm
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    // Get the current Git commit hash for tagging the image
                    def gitHash = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()

                    // Build the Docker image with the Git commit hash as a tag
                    sh "docker build -t ${DOCKER_IMAGE}:${gitHash} -t ${DOCKER_IMAGE}:latest ."
                }
            }
        }

        stage('Push to DockerHub') {
            steps {
                withCredentials([usernamePassword(credentialsId: DOCKERHUB_CREDENTIALS, usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    script {
                        // Login to DockerHub
                        sh "echo $DOCKER_PASS | docker login --username $DOCKER_USER --password-stdin"

                        // Push the 'latest' and commit-tagged images to DockerHub
                        sh "docker push ${DOCKER_IMAGE}:latest"
                        sh "docker push ${DOCKER_IMAGE}:${sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()}"
                    }
                }
            }
        }

    



        stage('Deploy to Kubernetes') {
            steps {
                sh """
                    # Configure kubectl to use the kubeconfig file on the Jenkins server
                    export KUBECONFIG=/var/lib/jenkins/.kube/config

                    # Apply the Kubernetes Deployment and Service manifests
                    echo "Applying Kubernetes Deployment..."
                    kubectl apply -f deployment.yaml
                    echo "Applying Kubernetes Service..."
                    kubectl apply -f service.yaml
                """
            }
        }
    }
}