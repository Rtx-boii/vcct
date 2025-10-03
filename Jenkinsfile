pipeline {
    agent any

    environment {
        DOCKER_USER  = "nilessh"
        DOCKER_PASS  = credentials('docker-hub-creds')
        GITHUB_CREDS = credentials('github-creds')
        REPO_URL     = 'https://github.com/Rtx-boii/vcct.git'
        ALL_SERVICES = "dhcp-server,dns-server,squid-proxy" // comma-separated string
    }

    triggers {
        cron('H/10 * * * *')
        pollSCM('')
    }

    stages {
        stage('Checkout Repository') {
            steps {
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: 'vcct-setup']],
                    userRemoteConfigs: [[url: env.REPO_URL, credentialsId: 'github-creds']],
                    extensions: [[$class: 'CloneOption', depth: 0, noTags: false, reference: '', shallow: false]]
                ])
            }
        }

        stage('Detect Changes & Prepare Services') {
            steps {
                script {
                    def servicesList = env.ALL_SERVICES.split(',')

                    // Use last successful commit or previous commit for diff
                    def lastCommit = env.GIT_PREVIOUS_SUCCESSFUL_COMMIT ?: sh(script: "git rev-parse HEAD~1", returnStdout: true).trim()
                    def changedFiles = sh(script: "git diff --name-only ${lastCommit} HEAD || true", returnStdout: true).trim().split("\n")
                    echo "Changed files: ${changedFiles}"

                    def versions = readYaml(file: 'versions.yml')
                    def servicesToBuild = []
                    def servicesToRestart = []

                    if (changedFiles.any { it == 'docker-compose.yml' || it == 'versions.yml' }) {
                        echo "Full blueprint change detected. All services will be recreated."
                        servicesToBuild = servicesList
                    } else {
                        servicesList.each { service ->
                            def hasDockerChange = changedFiles.any { it.startsWith("${service}/Dockerfile") || it.startsWith("${service}/entrypoint.sh") || it.startsWith("${service}/startup.sh") }
                            def hasConfigChange = changedFiles.any { it.startsWith("${service}/") }

                            if (hasDockerChange) {
                                servicesToBuild << service
                                versions[service] = (versions.get(service, 0) as int) + 1
                            } else if (hasConfigChange) {
                                servicesToRestart << service
                            }
                        }
                    }

                    servicesToRestart = servicesToRestart.unique().findAll { !servicesToBuild.contains(it) }
                    echo "Services to Build: ${servicesToBuild}"
                    echo "Services to Restart: ${servicesToRestart}"

                    writeYaml(file: 'versions.yml', data: versions, overwrite: true)
                    writeFile(file: "versions.env", text: versions.collect { k, v -> "${k.replace('-', '_').toUpperCase()}_VERSION=${v}" }.join("\n"))
                    writeFile(file: "build-services.txt", text: servicesToBuild.join("\n"))
                    writeFile(file: "restart-services.txt", text: servicesToRestart.join("\n"))
                }
            }
        }

        stage('Build & Push Docker Images') {
            steps {
                script {
                    def servicesToBuild = readFile("build-services.txt").trim().split("\n").findAll { it }
                    if (servicesToBuild) {
                        def versions = readYaml(file: 'versions.yml')
                        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                            sh 'echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin'
                        }
                        servicesToBuild.each { service ->
                            def version = versions[service]
                            echo "Building ${service}:${version}"
                            dir(service) {
                                sh """
                                docker build --no-cache -t ${DOCKER_USER}/${service}:${version} .
                                docker push ${DOCKER_USER}/${service}:${version}
                                docker tag ${DOCKER_USER}/${service}:${version} ${DOCKER_USER}/${service}:latest
                                docker push ${DOCKER_USER}/${service}:latest
                                """
                            }
                        }
                    } else {
                        echo "No images to build."
                    }
                }
            }
        }

        stage('Deploy / Restart Services') {
            steps {
                script {
                    def servicesList = env.ALL_SERVICES.split(',')
                    def servicesToBuild = readFile("build-services.txt").trim().split("\n").findAll { it }
                    def servicesToRestart = readFile("restart-services.txt").trim().split("\n").findAll { it }

                    if (servicesToBuild.empty && servicesToRestart.empty && sh(script: "git diff --name-only HEAD~1 HEAD", returnStdout: true).trim().any { it == 'docker-compose.yml' || it == 'versions.yml' }) {
                        echo "Full docker-compose reset due to blueprint change."
                        sh "docker compose down"
                        sh "set -a; . ${env.WORKSPACE}/versions.env; set +a; docker compose up -d"
                    } else {
                        if (servicesToBuild) {
                            echo "Recreating services with new images: ${servicesToBuild}"
                            sh "set -a; . ${env.WORKSPACE}/versions.env; set +a; docker compose up -d --no-deps --force-recreate ${servicesToBuild.join(' ')}"
                        }
                        if (servicesToRestart) {
                            echo "Restarting services with config changes: ${servicesToRestart}"
                            sh "docker compose up -d --no-deps --force-recreate ${servicesToRestart.join(' ')}"
                        }
                    }
                }
            }
        }

        stage('Post-Deployment Health Check') {
            steps {
                script {
                    def servicesList = env.ALL_SERVICES.split(',')
                    def servicesToCheck = readFile("build-services.txt").trim().split("\n").findAll { it }
                    if (!servicesToCheck) { servicesToCheck = servicesList }
                    servicesToCheck.each { service ->
                        echo "Waiting 20s for ${service} to initialize..."
                        sleep 20
                        def status = sh(script: "docker inspect --format='{{.State.Health.Status}}' ${service} 2>/dev/null || echo 'unhealthy'", returnStdout: true).trim()
                        if (status != "healthy") {
                            error("Health check failed for ${service} (status: ${status})")
                        } else {
                            echo "✅ ${service} is healthy."
                        }
                    }
                }
            }
        }

        stage('Commit Version Update') {
            steps {
                script {
                    def gitStatus = sh(script: 'git status --porcelain versions.yml', returnStdout: true).trim()
                    if (gitStatus) {
                        echo "Committing updated versions.yml"
                        withCredentials([usernamePassword(credentialsId: 'github-creds', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
                            sh """
                            git config user.email "jenkins@ci.com"
                            git config user.name "Jenkins CI"
                            git remote set-url origin https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/Rtx-boii/vcct.git
                            git add versions.yml
                            git commit -m "ci: Update service versions [skip ci]"
                            git push origin HEAD:vcct-setup
                            """
                        }
                    } else {
                        echo "No version changes to commit."
                    }
                }
            }
        }
    }

    post {
        failure {
            script {
                echo "Failure detected, rolling back services..."
                def servicesList = env.ALL_SERVICES.split(',')
                def currentVersions = readYaml(file: 'versions.yml')
                def oldVersionsContent = sh(script: "git show HEAD~1:versions.yml", returnStdout: true).trim()
                def oldVersions = readYaml(text: oldVersionsContent)
                oldVersions.keySet().each { service ->
                    if (currentVersions[service] != oldVersions[service]) {
                        echo "Rolling back ${service} to version ${oldVersions[service]}"
                        sh "export ${service.replace('-', '_').toUpperCase()}_VERSION=${oldVersions[service]}; docker compose up -d --no-deps --force-recreate ${service}"
                        currentVersions[service] = oldVersions[service]
                    }
                }
                writeYaml(file: 'versions.yml', data: currentVersions, overwrite: true)
            }
        }
        always {
            sh 'rm -f build-services.txt restart-services.txt versions.env'
        }
    }
}
