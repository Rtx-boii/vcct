pipeline {
    agent any

    environment {
        DOCKER_USER = 'nilessh'
        VERSION_FILE = 'versions.yml'
        DOCKER_HUB_CREDS = credentials('docker-hub-creds')
        GITHUB_CREDS = credentials('github-creds')
    }

    stages {
        stage('Checkout SCM') {
            steps {
                checkout([$class: 'GitSCM',
                    branches: [[name: '*/vcct-setup']],
                    userRemoteConfigs: [[url: 'https://github.com/Rtx-boii/vcct.git', credentialsId: 'github-creds']]
                ])
            }
        }

        stage('Docker Login') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKER_USER_ENV', passwordVariable: 'DOCKER_PASS_ENV')]) {
                    sh """
                        docker logout || true
                        echo \$DOCKER_PASS_ENV | docker login -u \$DOCKER_USER_ENV --password-stdin
                    """
                }
            }
        }

        stage('Cleanup Old Containers') {
            steps {
                script {
                    def services = ['dhcp-server','dns-server','squid-proxy']
                    for (svc in services) {
                        def containerId = sh(script: "docker ps -aq -f name=^${svc}\$", returnStdout: true).trim()
                        if (containerId) {
                            echo "Removing old container ${svc}..."
                            sh "docker rm -f ${containerId}"
                        }
                    }
                }
            }
        }

        stage('Initial Compose Status Check') {
            steps {
                script {
                    echo "Checking docker-compose services..."
                    def versionMap = [:]
                    if (fileExists("${VERSION_FILE}")) {
                        versionMap = readYaml file: "${VERSION_FILE}"
                    }

                    def services = ['dhcp-server','dns-server','squid-proxy']
                    for (svc in services) {
                        def version = versionMap[svc]
                        if (!version || version.toInteger() < 1) {
                            version = '1'
                            versionMap[svc] = version
                            writeYaml file: "${VERSION_FILE}", data: versionMap, overwrite: true
                        }

                        // Export versions as environment variables for Compose
                        env."${svc.toUpperCase().replace('-', '_')}_VERSION" = version
                    }
                }
            }
        }

        stage('Start Services') {
            steps {
                script {
                    echo "Starting all services via Docker Compose..."
                    sh "docker compose pull"
                    sh "docker compose up -d"
                }
            }
        }

        stage('Detect Changes') {
            steps {
                script {
                    def changedFiles = sh(script: "git diff --name-only HEAD~1 HEAD", returnStdout: true).trim().split("\n")
                    echo "Changed files: ${changedFiles}"

                    env.COMPOSE_CHANGED = (changedFiles.contains('docker-compose.yml')) ? 'true' : 'false'
                    env.VERSION_CHANGED = (changedFiles.contains("${VERSION_FILE}")) ? 'true' : 'false'

                    env.REBUILD_SERVICES = ''
                    env.RESTART_SERVICES = ''

                    def serviceFolders = ['dhcp-server','dns-server','squid-proxy']
                    for (svc in serviceFolders) {
                        if (changedFiles.any { it.startsWith("${svc}/Dockerfile") || it.startsWith("${svc}/entrypoint.sh") }) {
                            env.REBUILD_SERVICES += "${svc} "
                        } else if (changedFiles.any { it.startsWith("${svc}/") }) {
                            env.RESTART_SERVICES += "${svc} "
                        }
                    }
                }
            }
        }

        stage('Deploy Compose Change') {
            when { expression { env.COMPOSE_CHANGED == 'true' } }
            steps {
                sh "docker compose down && docker compose up -d"
            }
        }

        stage('Restart Version Changed Services') {
            when { expression { env.VERSION_CHANGED == 'true' } }
            steps {
                script {
                    def versionMap = readYaml file: "${VERSION_FILE}"
                    for (svc in versionMap.keySet()) {
                        def version = versionMap[svc]
                        echo "Restarting ${svc} with version ${version}"
                        sh "docker pull ${DOCKER_USER}/${svc}:${version}"
                        sh "docker compose up -d ${svc}"
                    }
                }
            }
        }

        stage('Build, Push & Deploy') {
            when { expression { env.REBUILD_SERVICES?.trim() } }
            steps {
                script {
                    def servicesToBuild = env.REBUILD_SERVICES.trim().split(" ")
                    def versionMap = readYaml file: "${VERSION_FILE}"

                    for (svc in servicesToBuild) {
                        // Increment version
                        def version = versionMap[svc].toInteger() + 1
                        versionMap[svc] = version
                        writeYaml file: "${VERSION_FILE}", data: versionMap, overwrite: true

                        echo "Building ${svc} image with version ${version}"
                        sh "docker build -t ${DOCKER_USER}/${svc}:${version} ./${svc}"
                        sh "docker push ${DOCKER_USER}/${svc}:${version}"
                        sh "docker compose up -d ${svc}"
                    }
                }
            }
        }

        stage('Health Check & Rollback') {
            steps {
                script {
                    def services = ['dhcp-server','dns-server','squid-proxy']
                    def versionMap = readYaml file: "${VERSION_FILE}"
                    for (svc in services) {
                        sleep 60
                        def state = sh(script: "docker inspect -f '{{.State.Running}}' ${svc}", returnStdout: true).trim()
                        if (state != 'true') {
                            echo "${svc} is not healthy! Rolling back..."
                            def prevVersion = versionMap[svc].toInteger() - 1
                            sh "docker pull ${DOCKER_USER}/${svc}:${prevVersion}"
                            sh "docker compose up -d ${svc}"
                            versionMap[svc] = prevVersion
                            writeYaml file: "${VERSION_FILE}", data: versionMap, overwrite: true
                        } else {
                            echo "${svc} is healthy."
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            sh 'docker logout'
            echo "Pipeline completed."
        }
    }
}
