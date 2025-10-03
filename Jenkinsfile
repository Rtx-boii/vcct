pipeline {
    agent any

    environment {
        DOCKER_USER  = "nilessh"
        DOCKER_PASS  = credentials('docker-hub-creds')
        GITHUB_CREDS = credentials('github-creds')
        REPO_URL     = 'https://github.com/Rtx-boii/vcct.git'
        GIT_PREVIOUS_COMMIT = sh(script: "echo ${env.GIT_PREVIOUS_SUCCESSFUL_COMMIT ?: 'HEAD~1'}", returnStdout: true).trim()
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
                anyOf {
                    triggeredBy 'com.cloudbees.jenkins.GitHubPushCause'
                    triggeredBy 'SCMPollingCause'
                    triggeredBy 'UserIdCause'
                }
            }
            steps {
                script {
                    // Robust diff: Use diff-tree for commit-to-commit changes
                    def changedFiles = sh(script: "git diff-tree --no-commit-id --name-only -r ${GIT_PREVIOUS_COMMIT} ${env.GIT_COMMIT} || true", returnStdout: true).trim().split("\n")
                    echo "Changed files since last successful build: ${changedFiles}"
                    echo "DEBUG: GIT_PREVIOUS_COMMIT=${GIT_PREVIOUS_COMMIT}, GIT_COMMIT=${env.GIT_COMMIT}"
                    echo "DEBUG: Raw diff-tree: ${sh(script: 'git diff-tree --no-commit-id --name-only -r ${GIT_PREVIOUS_COMMIT} ${env.GIT_COMMIT}', returnStdout: true)}"
                    echo "DEBUG: Changed files list: ${changedFiles.join(', ')}"
                    
                    def servicesToBuild = []; def servicesToRestart = []; def allServices = ['dhcp-server', 'dns-server', 'squid-proxy']; def versions = readYaml file: 'versions.yml'
                    
                    if (!changedFiles.any { it == 'docker-compose.yml' || it == 'versions.yml' }) {
                        allServices.each { service ->
                            def hasBuildFile = changedFiles.any { it.startsWith("${service}/Dockerfile") || it.startsWith("${service}/entrypoint.sh") || it.startsWith("${service}/startup.sh") }
                            def hasOtherFile = changedFiles.any { it.startsWith("${service}/") }
                            echo "DEBUG: For ${service} - Build trigger: ${hasBuildFile}, Restart trigger: ${hasOtherFile}"
                            if (hasBuildFile) {
                                servicesToBuild << service; def currentVersion = versions.get(service, 0) as int; versions[service] = currentVersion + 1
                            } else if (hasOtherFile) {
                                servicesToRestart << service
                            }
                        }
                    }
                    
                    servicesToRestart = servicesToRestart.unique().findAll { !servicesToBuild.contains(it) }; echo "Services to Build/Rebuild: ${servicesToBuild}"; echo "Services to Recreate (config change): ${servicesToRestart}";
                    
                    writeYaml file: 'versions.yml', data: versions, overwrite: true; def versionsEnv = versions.collect { service, version -> "${service.replace('-', '_').toUpperCase()}_VERSION=${version}" }.join("\n");
                    writeFile file: "versions.env", text: versionsEnv; writeFile file: "build-services.txt", text: servicesToBuild.join("\n"); writeFile file: "restart-services.txt", text: servicesToRestart.join("\n")
                }
            }
        }

        stage('Build and Push New Images') {
            when {
                anyOf {
                    triggeredBy 'com.cloudbees.jenkins.GitHubPushCause'
                    triggeredBy 'SCMPollingCause'
                    triggeredBy 'UserIdCause'
                }
            }
            steps {
                script {
                    def servicesToBuild = readFile("build-services.txt").trim().split("\n").findAll { it }; if (servicesToBuild) { def versions = readYaml file: 'versions.yml'; withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) { sh 'echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin' }; servicesToBuild.each { service -> def newVersion = versions[service]; echo "Building ${service} with version: ${newVersion}"; dir(service) { sh """ docker build --no-cache -t ${DOCKER_USER}/${service}:${newVersion} . docker push ${DOCKER_USER}/${service}:${newVersion} docker tag ${DOCKER_USER}/${service}:${newVersion} ${DOCKER_USER}/${service}:latest docker push ${DOCKER_USER}/${service}:latest """ } } } else { echo "No new images to build." }
                }
            }
        }

        stage('Deploy and Restart Services') {
            when {
                anyOf {
                    triggeredBy 'com.cloudbees.jenkins.GitHubPushCause'
                    triggeredBy 'SCMPollingCause'
                    triggeredBy 'UserIdCause'
                }
            }
            steps {
                script {
                    // Use same robust diff-tree here
                    def changedFiles = sh(script: "git diff-tree --no-commit-id --name-only -r ${GIT_PREVIOUS_COMMIT} ${env.GIT_COMMIT} || true", returnStdout: true).trim().split("\n")
                    
                    if (changedFiles.any { it == 'docker-compose.yml' || it == 'versions.yml' }) {
                        echo "Blueprint change detected in docker-compose.yml or versions.yml. Performing a full environment reset."
                        sh "docker compose down"
                        sh "set -a; . ${env.WORKSPACE}/versions.env; set +a; docker compose up -d"
                    } else {
                        echo "Code change detected. Performing standard deployment."
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
                anyOf {
                    triggeredBy 'com.cloudbees.jenkins.GitHubPushCause'
                    triggeredBy 'SCMPollingCause'
                    triggeredBy 'UserIdCause'
                }
            }
            steps {
                script {
                    // Use diff-tree here too
                    def changedFiles = sh(script: "git diff-tree --no-commit-id --name-only -r ${GIT_PREVIOUS_COMMIT} ${env.GIT_COMMIT} || true", returnStdout: true).trim().split("\n")
                    def servicesToCheck = []; 
                    if (changedFiles.any { it == 'docker-compose.yml' || it == 'versions.yml' }) { 
                        servicesToCheck = ['dhcp-server', 'dns-server', 'squid-proxy'] 
                    } else { 
                        servicesToCheck = readFile("build-services.txt").trim().split("\n").findAll { it } 
                    }; 
                    if (servicesToCheck) { 
                        echo "Performing post-deployment health check for: ${servicesToCheck}"; 
                        servicesToCheck.each { service -> 
                            echo "Waiting 20 seconds for ${service} to initialize..."; 
                            sleep 20; 
                            def status = sh(script: "docker inspect --format='{{.State.Health.Status}}' ${service} 2>/dev/null || echo 'unhealthy'", returnStdout: true).trim(); 
                            if (status != "healthy") { 
                                error("Health check failed for newly deployed service: ${service} (status: ${status}). Initiating automatic rollback.") 
                            } else { 
                                echo "✅ Health check passed for ${service}." 
                            } 
                        } 
                    } else { 
                        echo "No newly deployed services to check." 
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
                    echo "Running health check and self-heal for all services..."; def versions = readYaml file: 'versions.yml'; def versionsEnv = versions.collect { service, version -> "${service.replace('-', '_').toUpperCase()}_VERSION=${version}" }.join("\n"); writeFile file: "versions.env", text: versionsEnv; def allServices = ['dhcp-server', 'dns-server', 'squid-proxy']; allServices.each { service -> def status = sh(script: "docker inspect --format='{{.State.Health.Status}}' ${service} 2>/dev/null || echo 'unhealthy'", returnStdout: true).trim(); if (status != "healthy") { echo "⚠️ Health check failed for ${service} (status: ${status}). Attempting to heal/recreate..."; sh "set -a; . ${env.WORKSPACE}/versions.env; set +a; docker compose up -d --no-deps --force-recreate ${service}" } else { echo "✅ Health check passed for ${service}." } }
                }
            }
        }

        stage('Commit Version Update') {
            when {
                anyOf {
                    triggeredBy 'com.cloudbees.jenkins.GitHubPushCause'
                    triggeredBy 'SCMPollingCause'
                    triggeredBy 'TimerTrigger'
                    triggeredBy 'UserIdCause'
                }
            }
            steps {
                script {
                    echo "DEBUG: Current git status for versions.yml:"
                    sh 'git status --porcelain versions.yml || echo "No changes or file missing"'
                    sh 'git diff versions.yml || echo "No diff"'
                    def gitStatus = sh(script: 'git status --porcelain versions.yml', returnStdout: true).trim(); if (gitStatus) { echo "versions.yml has changed. Committing updates..."; withCredentials([usernamePassword(credentialsId: 'github-creds', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) { sh """ git config user.email "jenkins@ci.com"; git config user.name "Jenkins CI"; git remote set-url origin https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/Rtx-boii/vcct.git; git add versions.yml; git commit -m "ci: Update service versions [skip ci]"; git push origin HEAD:vcct-setup -v """ } } else { echo "No version changes to commit." }
                }
            }
        }
    }

    post {
        failure {
            script {
                echo "A failure occurred. Checking for services that need to be rolled back."; def currentVersions = readYaml file: 'versions.yml'; def oldVersionsContent = sh(script: "git show ${GIT_PREVIOUS_COMMIT}:versions.yml", returnStdout: true).trim(); def oldVersions = readYaml text: oldVersionsContent; oldVersions.keySet().each { service -> if (currentVersions.get(service) != oldVersions.get(service)) { echo "Rolling back ${service} from version ${currentVersions.get(service, 'N/A')} to ${oldVersions.get(service, 'N/A')}." ; sh "export ${service.replace('-', '_').toUpperCase()}_VERSION=${oldVersions[service]}; docker compose up -d --no-deps --force-recreate ${service}"; currentVersions[service] = oldVersions[service] } }; writeYaml file: 'versions.yml', data: currentVersions, overwrite: true; echo "Workspace versions.yml has been updated to reflect the rollback."
            }
        }
        always {
            sh 'rm -f build-services.txt restart-services.txt versions.env'
        }
    }
}
