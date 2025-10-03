pipeline {
    agent any

    environment {
        DOCKER_USER  = "nilessh"
        DOCKER_PASS  = credentials('docker-hub-creds')
        GITHUB_CREDS = credentials('github-creds')
        REPO_URL     = 'https://github.com/Rtx-boii/vcct.git'
    }

    triggers {
        cron('H/10 * * * *')
        pollSCM('')
    }

    stages {

        stage('Checkout Repository') {
            steps {
                git branch: 'vcct-setup', url: REPO_URL, credentialsId: 'github-creds'
            }
        }

        stage('Detect Changes & Prepare for Build') {
            when {
                not { triggeredBy 'TimerTrigger' } // skip cron
            }
            steps {
                script {
                    def previousCommit = sh(script: "git rev-parse HEAD~1", returnStdout: true).trim()
                    def currentCommit = sh(script: "git rev-parse HEAD", returnStdout: true).trim()
                    def changedFiles = sh(script: "git diff-tree --no-commit-id --name-only -r ${previousCommit} ${currentCommit} || true", returnStdout: true).trim().split("\n")

                    echo "Changed files: ${changedFiles}"

                    def allServices = ['dhcp-server', 'dns-server', 'squid-proxy']
                    def versions = readYaml file: 'versions.yml'

                    def servicesToBuild = []
                    def servicesToRestart = []

                    if (!changedFiles.any { it in ['docker-compose.yml','versions.yml'] }) {
                        allServices.each { service ->
                            def hasBuildFile = changedFiles.any { it.startsWith("${service}/Dockerfile") || it.startsWith("${service}/entrypoint.sh") || it.startsWith("${service}/startup.sh") }
                            def hasOtherFile = changedFiles.any { it.startsWith("${service}/") }
                            if (hasBuildFile) {
                                servicesToBuild << service
                                versions[service] = (versions.get(service,0) as int) + 1
                            } else if (hasOtherFile) {
                                servicesToRestart << service
                            }
                        }
                    }

                    servicesToRestart = servicesToRestart.unique().findAll { !servicesToBuild.contains(it) }

                    echo "Services to Build: ${servicesToBuild}"
                    echo "Services to Restart: ${servicesToRestart}"

                    writeYaml file: 'versions.yml', data: versions, overwrite: true
                    def versionsEnv = versions.collect { k,v -> "${k.replace('-', '_').toUpperCase()}_VERSION=${v}" }.join("\n")
                    writeFile file: 'versions.env', text: versionsEnv
                    writeFile file: 'build-services.txt', text: servicesToBuild.join("\n")
                    writeFile file: 'restart-services.txt', text: servicesToRestart.join("\n")
                }
            }
        }

        stage('Build and Push New Images') {
            when {
                not { triggeredBy 'TimerTrigger' } // skip cron
            }
            steps {
                script {
                    def servicesToBuild = readFile("build-services.txt").trim().split("\n").findAll { it }
                    if (servicesToBuild) {
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
                    } else {
                        echo "No images to build."
                    }
                }
            }
        }

        stage('Deploy and Restart Services') {
            when {
                not { triggeredBy 'TimerTrigger' } // skip cron
            }
            steps {
                script {
                    def changedFiles = sh(script: "git diff-tree --no-commit-id --name-only HEAD~1 HEAD || true", returnStdout: true).trim().split("\n")

                    if (changedFiles.any { it in ['docker-compose.yml','versions.yml'] }) {
                        echo "Full environment reset due to blueprint changes"
                        sh "docker compose down"
                        sh "set -a; . ${env.WORKSPACE}/versions.env; set +a; docker compose up -d"
                    } else {
                        def servicesToBuild = readFile("build-services.txt").trim().split("\n").findAll { it }
                        def servicesToRestart = readFile("restart-services.txt").trim().split("\n").findAll { it }

                        if (servicesToBuild) {
                            sh "set -a; . ${env.WORKSPACE}/versions.env; set +a; docker compose up -d --no-deps --force-recreate ${servicesToBuild.join(' ')}"
                        }
                        if (servicesToRestart) {
                            echo "Recreating services with config changes: ${servicesToRestart}"
                            sh "docker compose up -d --no-deps --force-recreate ${servicesToRestart.join(' ')}"
                        }
                    }
                }
            }
        }

        stage('Post-Deployment Health Check') {
            when {
                not { triggeredBy 'TimerTrigger' } // skip cron
            }
            steps {
                script {
                    def servicesToCheck = readFile("build-services.txt").trim().split("\n").findAll { it }
                    if (!servicesToCheck) { servicesToCheck = ['dhcp-server', 'dns-server', 'squid-proxy'] }

                    servicesToCheck.each { service ->
                        echo "Waiting 20s for ${service}..."
                        sleep 20
                        def status = sh(script: "docker inspect --format='{{.State.Health.Status}}' ${service} 2>/dev/null || echo 'unhealthy'", returnStdout: true).trim()
                        if (status != "healthy") {
                            error("Health check failed for ${service} (status: ${status})")
                        } else {
                            echo "✅ Health check passed for ${service}"
                        }
                    }
                }
            }
        }

        stage('Monitor and Heal Services') {
            when {
                anyOf {
                    triggeredBy 'TimerTrigger'
                    triggeredBy 'UserIdCause'
                }
            }
            steps {
                script {
                    echo "Running scheduled health monitoring..."
                    def allServices = ['dhcp-server','dns-server','squid-proxy']
                    def versions = readYaml file: 'versions.yml'
                    def versionsEnv = versions.collect { k,v -> "${k.replace('-', '_').toUpperCase()}_VERSION=${v}" }.join("\n")
                    writeFile file: 'versions.env', text: versionsEnv

                    allServices.each { service ->
                        def status = sh(script: "docker inspect --format='{{.State.Health.Status}}' ${service} 2>/dev/null || echo 'unhealthy'", returnStdout: true).trim()
                        if (status != "healthy") {
                            echo "⚠️ Recreating unhealthy service: ${service}"
                            sh "set -a; . ${env.WORKSPACE}/versions.env; set +a; docker compose up -d --no-deps --force-recreate ${service}"
                        } else {
                            echo "✅ ${service} is healthy"
                        }
                    }
                }
            }
        }

        stage('Commit Version Update') {
            when {
                not { triggeredBy 'TimerTrigger' } // skip cron
            }
            steps {
                script {
                    def gitStatus = sh(script: 'git status --porcelain versions.yml', returnStdout: true).trim()
                    if (gitStatus) {
                        echo "Committing versions.yml changes..."
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
        failure {
            script {
                echo "Failure detected. Attempting rollback..."
                def currentVersions = readYaml file: 'versions.yml'
                def oldVersionsContent = sh(script: "git show HEAD~1:versions.yml", returnStdout: true).trim()
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
