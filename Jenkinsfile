pipeline {
    agent any

    environment {
        DOCKER_USER  = "nilessh"
        DOCKER_PASS  = credentials('docker-hub-creds')
        GITHUB_CREDS = credentials('github-creds')
        REPO_URL     = 'https://github.com/Rtx-boii/vcct.git'
    }

    triggers {
        cron('H/10 * * * *') // Health check every 10 minutes
        pollSCM('')          // Detect SCM changes
    }

    stages {

        stage('Checkout Repository') {
            steps {
                git branch: 'vcct-setup', url: REPO_URL, credentialsId: 'github-creds'
            }
        }

        stage('Detect Changes & Prepare Build') {
            when {
                anyOf {
                    triggeredBy 'com.cloudbees.jenkins.GitHubPushCause'
                    triggeredBy 'SCMPollingCause'
                    triggeredBy 'UserIdCause'
                }
            }
            steps {
                script {
                    def allServices = ['dhcp-server','dns-server','squid-proxy']
                    def dockerfileMap = [
                        'dhcp-server': ['Dockerfile','Dockerfile.sh'],
                        'dns-server':  ['Dockerfile','entrypoint.sh'],
                        'squid-proxy':['Dockerfile','start-squid.sh']
                    ]

                    def changedFiles = sh(script: "git diff-tree --no-commit-id --name-only -r ${env.GIT_PREVIOUS_SUCCESSFUL_COMMIT ?: 'HEAD~1'} ${env.GIT_COMMIT}", returnStdout: true).trim().split("\n")
                    echo "Changed files: ${changedFiles}"

                    def servicesToBuild = []
                    def servicesToRestart = []
                    def versions = readYaml(file: 'versions.yml')

                    allServices.each { service ->
                        def rebuild = changedFiles.any { file -> dockerfileMap[service].any { file.endsWith(it) } }
                        def configChange = changedFiles.any { file -> file.startsWith("${service}/") } && !rebuild
                        if (rebuild) {
                            servicesToBuild << service
                            versions[service] = (versions[service] ?: 0) + 1
                        } else if (configChange) {
                            servicesToRestart << service
                        }
                    }

                    // Handle full blueprint changes
                    if (changedFiles.any { it == 'docker-compose.yml' || it == 'versions.yml' }) {
                        servicesToBuild = allServices
                        versions = allServices.collectEntries { [(it): (versions[it] ?: 0) + 1] }
                        servicesToRestart = []
                    }

                    echo "Services to build: ${servicesToBuild}"
                    echo "Services to restart: ${servicesToRestart}"

                    writeYaml file: 'versions.yml', data: versions, overwrite: true
                    writeFile file: 'build-services.txt', text: servicesToBuild.join("\n")
                    writeFile file: 'restart-services.txt', text: servicesToRestart.join("\n")

                    def versionsEnv = versions.collect { k,v -> "${k.replace('-','_').toUpperCase()}_VERSION=${v}" }.join("\n")
                    writeFile file: 'versions.env', text: versionsEnv
                }
            }
        }

        stage('Build and Push Images') {
            when {
                anyOf {
                    triggeredBy 'com.cloudbees.jenkins.GitHubPushCause'
                    triggeredBy 'SCMPollingCause'
                    triggeredBy 'UserIdCause'
                }
            }
            steps {
                script {
                    def servicesToBuild = readFile('build-services.txt').trim().split("\n").findAll { it }
                    if (!servicesToBuild) {
                        echo "No services to build."
                        return
                    }

                    def versions = readYaml(file: 'versions.yml')
                    withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                        sh 'echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin'
                    }

                    servicesToBuild.each { service ->
                        def newVersion = versions[service]
                        echo "Building ${service} version ${newVersion}"
                        dir(service) {
                            sh """
                                docker build -t ${DOCKER_USER}/${service}:${newVersion} .
                                docker push ${DOCKER_USER}/${service}:${newVersion}
                                docker tag ${DOCKER_USER}/${service}:${newVersion} ${DOCKER_USER}/${service}:latest
                                docker push ${DOCKER_USER}/${service}:latest
                            """
                        }
                    }
                }
            }
        }

        stage('Deploy Services') {
            when {
                anyOf {
                    triggeredBy 'com.cloudbees.jenkins.GitHubPushCause'
                    triggeredBy 'SCMPollingCause'
                    triggeredBy 'UserIdCause'
                }
            }
            steps {
                script {
                    def servicesToBuild = readFile('build-services.txt').trim().split("\n").findAll { it }
                    def servicesToRestart = readFile('restart-services.txt').trim().split("\n").findAll { it }

                    if (servicesToBuild) {
                        sh "set -a; . versions.env; set +a; docker compose up -d --no-deps --force-recreate ${servicesToBuild.join(' ')}"
                    }

                    if (servicesToRestart) {
                        sh "docker compose up -d --no-deps --force-recreate ${servicesToRestart.join(' ')}"
                    }
                }
            }
        }

        stage('Post-Deployment Health Check') {
            when {
                anyOf {
                    triggeredBy 'com.cloudbees.jenkins.GitHubPushCause'
                    triggeredBy 'SCMPollingCause'
                    triggeredBy 'UserIdCause'
                }
            }
            steps {
                script {
                    def servicesToCheck = readFile('build-services.txt').trim().split("\n").findAll { it }
                    if (!servicesToCheck) {
                        echo "No services rebuilt, skipping health check."
                        return
                    }

                    servicesToCheck.each { service ->
                        echo "Waiting 20s for ${service} to initialize..."
                        sleep 20
                        def status = sh(script: "docker inspect --format='{{.State.Health.Status}}' ${service} 2>/dev/null || echo 'unhealthy'", returnStdout: true).trim()
                        if (status != "healthy") {
                            error("Health check failed for ${service} (status: ${status})")
                        } else {
                            echo "✅ ${service} is healthy"
                        }
                    }
                }
            }
        }

        stage('Health Monitoring (TimerTrigger)') {
            when {
                triggeredBy 'TimerTrigger'
            }
            steps {
                script {
                    def allServices = ['dhcp-server','dns-server','squid-proxy']
                    allServices.each { service ->
                        def status = sh(script: "docker inspect --format='{{.State.Health.Status}}' ${service} 2>/dev/null || echo 'unhealthy'", returnStdout: true).trim()
                        if (status != "healthy") {
                            echo "⚠️ ${service} unhealthy, recreating..."
                            sh "docker compose up -d --no-deps --force-recreate ${service}"
                        } else {
                            echo "✅ ${service} is healthy"
                        }
                    }
                }
            }
        }

        stage('Commit Version Updates') {
            when {
                anyOf {
                    triggeredBy 'com.cloudbees.jenkins.GitHubPushCause'
                    triggeredBy 'SCMPollingCause'
                    triggeredBy 'UserIdCause'
                }
            }
            steps {
                script {
                    def gitStatus = sh(script: "git status --porcelain versions.yml", returnStdout: true).trim()
                    if (gitStatus) {
                        withCredentials([usernamePassword(credentialsId: 'github-creds', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
                            sh """
                                git config user.email "jenkins@ci.com"
                                git config user.name "Jenkins CI"
                                git remote set-url origin https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/Rtx-boii/vcct.git
                                git add versions.yml
                                git commit -m "ci: Update service versions [skip ci]"
                                git push origin HEAD:vcct-setup -v
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
        always {
            sh 'rm -f build-services.txt restart-services.txt versions.env'
        }
    }
}
