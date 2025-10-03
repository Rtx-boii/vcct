pipeline {
    agent any

    environment {
        DOCKER_USER  = "nilessh"
        DOCKER_PASS  = credentials('docker-hub-creds')
        GITHUB_CREDS = credentials('github-creds')
        REPO_URL     = 'https://github.com/Rtx-boii/vcct.git'
        ALL_SERVICES = "dhcp-server,dns-server,squid-proxy"
    }

    triggers {
        cron('H/10 * * * *') // Run health check every 10 minutes
        pollSCM('H/5 * * * *') // Optional: check Git every 5 minutes
    }

    stages {

        stage('Checkout Repository') {
            steps {
                git branch: 'vcct-setup', url: REPO_URL, credentialsId: 'github-creds'
            }
        }

        stage('Detect Changes') {
            when {
                expression {
                    // Only run on Git-triggered builds
                    return currentBuild.getBuildCauses('hudson.triggers.SCMTrigger$SCMTriggerCause') ||
                           currentBuild.getBuildCauses('com.cloudbees.jenkins.GitHubPushCause') ||
                           currentBuild.getBuildCauses('hudson.model.UserIdCause')
                }
            }
            steps {
                script {
                    def changedFiles = sh(script: "git diff-tree --no-commit-id --name-only -r ${env.GIT_PREVIOUS_SUCCESSFUL_COMMIT ?: 'HEAD~1'} ${env.GIT_COMMIT}", returnStdout: true).trim().split("\n")
                    echo "Changed files: ${changedFiles}"

                    def servicesToBuild = []
                    def servicesToRestart = []
                    def allServices = env.ALL_SERVICES.split(',')

                    // Read versions file
                    def versions = readYaml file: 'versions.yml'

                    allServices.each { service ->
                        def dockerFiles = ["${service}/Dockerfile", "${service}/entrypoint.sh", "${service}/startup.sh", "${service}/start-squid.sh"]
                        def hasBuildFile = changedFiles.any { dockerFiles.contains(it) }
                        def hasOtherFile = changedFiles.any { it.startsWith("${service}/") }

                        if (hasBuildFile) {
                            servicesToBuild << service
                            versions[service] = (versions[service] ?: 0) + 1
                        } else if (hasOtherFile) {
                            servicesToRestart << service
                        }
                    }

                    // Remove duplicates
                    servicesToRestart = servicesToRestart.findAll { !servicesToBuild.contains(it) }

                    echo "Services to Build: ${servicesToBuild}"
                    echo "Services to Restart: ${servicesToRestart}"

                    writeFile file: "build-services.txt", text: servicesToBuild.join("\n")
                    writeFile file: "restart-services.txt", text: servicesToRestart.join("\n")

                    // Update versions file and environment file
                    writeYaml file: 'versions.yml', data: versions, overwrite: true
                    def versionsEnv = versions.collect { s,v -> "${s.replace('-', '_').toUpperCase()}_VERSION=${v}" }.join("\n")
                    writeFile file: "versions.env", text: versionsEnv
                }
            }
        }

        stage('Build and Push Images') {
            when {
                expression { return readFile('build-services.txt').trim() != '' }
            }
            steps {
                script {
                    def servicesToBuild = readFile('build-services.txt').trim().split("\n")
                    def versions = readYaml file: 'versions.yml'

                    withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                        sh 'echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin'
                    }

                    servicesToBuild.each { service ->
                        def newVersion = versions[service]
                        echo "Building ${service}:${newVersion}"
                        dir(service) {
                            sh """
                                docker build --no-cache -t ${DOCKER_USER}/${service}:${newVersion} .
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
            steps {
                script {
                    def servicesToBuild = readFile('build-services.txt').trim().split("\n").findAll { it }
                    def servicesToRestart = readFile('restart-services.txt').trim().split("\n").findAll { it }

                    sh "set -a; . ${env.WORKSPACE}/versions.env; set +a"

                    if (servicesToBuild) {
                        sh "docker compose up -d --no-deps --force-recreate ${servicesToBuild.join(' ')}"
                    }

                    if (servicesToRestart) {
                        sh "docker compose up -d --no-deps --force-recreate ${servicesToRestart.join(' ')}"
                    }
                }
            }
        }

        stage('Post-Deployment Health Check') {
            steps {
                script {
                    def services = env.ALL_SERVICES.split(',')
                    services.each { service ->
                        echo "Waiting 20s for ${service}..."
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

        stage('Health Monitoring (TimerTrigger)') {
            when {
                triggeredBy 'TimerTrigger'
            }
            steps {
                script {
                    def services = env.ALL_SERVICES.split(',')
                    sh "set -a; . ${env.WORKSPACE}/versions.env; set +a"
                    services.each { service ->
                        def status = sh(script: "docker inspect --format='{{.State.Health.Status}}' ${service} 2>/dev/null || echo 'unhealthy'", returnStdout: true).trim()
                        if (status != "healthy") {
                            echo "⚠️ ${service} unhealthy. Attempting auto-heal..."
                            sh "docker compose up -d --no-deps --force-recreate ${service}"
                        } else {
                            echo "✅ ${service} is healthy."
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
                    def gitStatus = sh(script: 'git status --porcelain versions.yml', returnStdout: true).trim()
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
                        echo "No version updates to commit."
                    }
                }
            }
        }
    }

    post {
        failure {
            script {
                echo "Failure detected. Attempting rollback..."
                def currentVersions = readYaml file: 'versions.yml'
                def oldVersionsContent = sh(script: "git show ${env.GIT_PREVIOUS_SUCCESSFUL_COMMIT ?: 'HEAD~1'}:versions.yml", returnStdout: true).trim()
                def oldVersions = readYaml text: oldVersionsContent

                oldVersions.keySet().each { service ->
                    if (currentVersions[service] != oldVersions[service]) {
                        echo "Rolling back ${service} from ${currentVersions[service]} to ${oldVersions[service]}"
                        sh "export ${service.replace('-', '_').toUpperCase()}_VERSION=${oldVersions[service]}; docker compose up -d --no-deps --force-recreate ${service}"
                        currentVersions[service] = oldVersions[service]
                    }
                }
                writeYaml file: 'versions.yml', data: currentVersions, overwrite: true
            }
        }
        always {
            sh 'rm -f build-services.txt restart-services.txt versions.env'
        }
    }
}
