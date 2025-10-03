pipeline {
    agent any

    environment {
        DOCKER_USER  = "nilessh"
        DOCKER_PASS  = credentials('docker-hub-creds')
        GITHUB_CREDS = credentials('github-creds')
        REPO_URL     = 'https://github.com/Rtx-boii/vcct.git'
        // This ensures there's always a valid commit to compare against, even on the very first build.
        GIT_PREVIOUS_COMMIT = sh(script: "echo ${env.GIT_PREVIOUS_SUCCESSFUL_COMMIT ?: 'HEAD~1'}", returnStdout: true).trim()
    }

    triggers {
        // Runs every 10 minutes to perform the 'Periodic Health Check'.
        cron('H/10 * * * *')
        // Allows GitHub webhooks to trigger the pipeline on a code push.
        pollSCM('')
    }

    stages {

        // -------------------------------
        // Stage 1: Checkout Repository (Runs for ALL triggers)
        // -------------------------------
        stage('Checkout Repository') {
            steps {
                git branch: 'vcct-setup', url: REPO_URL, credentialsId: 'github-creds'
            }
        }

        // -------------------------------
        // Stage 2: Detect Changes (Runs for GitHub commits AND Manual builds)
        // -------------------------------
        stage('Detect Changes & Prepare for Build') {
            when {
                anyOf {
                    triggeredBy 'SCMTrigger'  // Triggered by a GitHub push
                    triggeredBy 'UserIdCause' // Triggered by clicking "Build Now"
                }
            }
            steps {
                script {
                    def changedFiles = sh(script: "git diff --name-only ${GIT_PREVIOUS_COMMIT} ${env.GIT_COMMIT} || true", returnStdout: true).trim().split("\n")
                    echo "Changed files since last successful build: ${changedFiles}"
                    
                    def servicesToBuild = []
                    def servicesToRestart = []
                    def allServices = ['dhcp-server', 'dns-server', 'squid-proxy']
                    def versions = readYaml file: 'versions.yml'
                    
                    // Only increment versions if it's a code change, not a blueprint (yml) change.
                    if (!changedFiles.any { it == 'docker-compose.yml' || it == 'versions.yml' }) {
                        allServices.each { service ->
                            if (changedFiles.any { it.startsWith("${service}/Dockerfile") || it.startsWith("${service}/entrypoint.sh") || it.startsWith("${service}/startup.sh") }) {
                                servicesToBuild << service
                                def currentVersion = versions.get(service, 0) as int
                                versions[service] = currentVersion + 1
                            } else if (changedFiles.any { it.startsWith("${service}/") }) {
                                servicesToRestart << service
                            }
                        }
                    }
                    
                    servicesToRestart = servicesToRestart.unique().findAll { !servicesToBuild.contains(it) }

                    echo "Services to Build/Rebuild: ${servicesToBuild}"
                    echo "Services to Recreate (config change): ${servicesToRestart}"
                    
                    writeYaml file: 'versions.yml', data: versions, overwrite: true
                    def versionsEnv = versions.collect { service, version -> "${service.replace('-', '_').toUpperCase()}_VERSION=${version}" }.join("\n")
                    writeFile file: "versions.env", text: versionsEnv
                    writeFile file: "build-services.txt", text: servicesToBuild.join("\n")
                    writeFile file: "restart-services.txt", text: servicesToRestart.join("\n")
                }
            }
        }

        // -------------------------------
        // Stage 3: Build Images (Runs for GitHub commits AND Manual builds)
        // -------------------------------
        stage('Build and Push New Images') {
            when {
                anyOf {
                    triggeredBy 'SCMTrigger'
                    triggeredBy 'UserIdCause'
                }
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
                            echo "Building ${service} with version: ${newVersion}"
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
                        echo "No new images to build."
                    }
                }
            }
        }

        // -------------------------------
        // Stage 4: Deploy Services (Runs for GitHub commits AND Manual builds)
        // -------------------------------
        stage('Deploy and Restart Services') {
            when {
                anyOf {
                    triggeredBy 'SCMTrigger'
                    triggeredBy 'UserIdCause'
                }
            }
            steps {
                script {
                    def changedFiles = sh(script: "git diff --name-only ${GIT_PREVIOUS_COMMIT} ${env.GIT_COMMIT} || true", returnStdout: true).trim().split("\n")
                    if (changedFiles.any { it == 'docker-compose.yml' }) {
                        echo "Structural change in docker-compose.yml detected. Performing a full environment reset."
                        sh "docker compose down"
                        sh "set -a; source ${env.WORKSPACE}/versions.env; set +a; docker compose up -d"
                    } else if (changedFiles.any { it == 'versions.yml' }) {
                        echo "Change in versions.yml detected. Performing a surgical deployment/rollback."
                        def oldVersionsContent = sh(script: "git show ${GIT_PREVIOUS_COMMIT}:versions.yml", returnStdout: true).trim()
                        def oldVersions = readYaml text: oldVersionsContent
                        def newVersions = readYaml file: 'versions.yml'
                        def servicesToDeploy = []
                        newVersions.keySet().each { service ->
                            if (newVersions[service] != oldVersions.get(service)) {
                                servicesToDeploy << service
                            }
                        }
                        if (servicesToDeploy) {
                            echo "Deploying version changes for services: ${servicesToDeploy}"
                            sh "set -a; source ${env.WORKSPACE}/versions.env; set +a; docker compose up -d --no-deps --force-recreate ${servicesToDeploy.join(' ')}"
                        }
                    } else {
                        echo "Code change detected. Performing standard deployment."
                        def servicesToBuild = readFile("build-services.txt").trim().split("\n").findAll { it }
                        def servicesToRestart = readFile("restart-services.txt").trim().split("\n").findAll { it }
                        if (servicesToBuild) {
                            sh "set -a; source ${env.WORKSPACE}/versions.env; set +a; docker compose up -d --no-deps --force-recreate ${servicesToBuild.join(' ')}"
                        }
                        if (servicesToRestart) {
                            echo "Recreating services with config changes: ${servicesToRestart}"
                            sh "docker compose up -d --no-deps --force-recreate ${servicesToRestart.join(' ')}"
                        }
                    }
                }
            }
        }

        // -------------------------------
        // Stage 5: Verify Deployment (Runs for GitHub commits AND Manual builds)
        // -------------------------------
        stage('Post-Deployment Health Check') {
            when {
                anyOf {
                    triggeredBy 'SCMTrigger'
                    triggeredBy 'UserIdCause'
                }
            }
            steps {
                script {
                    def servicesToCheck = []
                    def changedFiles = sh(script: "git diff --name-only ${GIT_PREVIOUS_COMMIT} ${env.GIT_COMMIT} || true", returnStdout: true).trim().split("\n")
                    if (changedFiles.any { it == 'docker-compose.yml' }) {
                        servicesToCheck = ['dhcp-server', 'dns-server', 'squid-proxy']
                    } else if (changedFiles.any { it == 'versions.yml' }) {
                        def oldVersionsContent = sh(script: "git show ${GIT_PREVIOUS_COMMIT}:versions.yml", returnStdout: true).trim()
                        def oldVersions = readYaml text: oldVersionsContent
                        def newVersions = readYaml file: 'versions.yml'
                        newVersions.keySet().each { service ->
                            if (newVersions[service] != oldVersions.get(service)) {
                                servicesToCheck << service
                            }
                        }
                    } else {
                        servicesToCheck = readFile("build-services.txt").trim().split("\n").findAll { it }
                    }
                    if (servicesToCheck) {
                        echo "Performing post-deployment health check for: ${servicesToCheck}"
                        servicesToCheck.each { service ->
                            echo "Waiting 20 seconds for ${service} to initialize..."
                            sleep 20
                            def status = sh(script: "docker inspect --format='{{.State.Health.Status}}' ${service} 2>/dev/null || echo 'unhealthy'", returnStdout: true).trim()
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

        // -------------------------------
        // Stage 6: Monitor Stability (Runs ONLY on the 10-minute schedule)
        // -------------------------------
        stage('Periodic Health Check') {
            when { triggeredBy 'TimerTrigger' }
            steps {
                script {
                    echo "Running periodic health check for all services..."
                    // This stage now reads versions.yml and prepares its own environment to prevent errors.
                    def versions = readYaml file: 'versions.yml'
                    def versionsEnv = versions.collect { service, version -> "${service.replace('-', '_').toUpperCase()}_VERSION=${version}" }.join("\n")
                    writeFile file: "versions.env", text: versionsEnv
                    
                    def allServices = ['dhcp-server', 'dns-server', 'squid-proxy']
                    allServices.each { service ->
                        def status = sh(script: "docker inspect --format='{{.State.Health.Status}}' ${service} 2>/dev/null || echo 'unhealthy'", returnStdout: true).trim()
                        if (status != "healthy") {
                            echo "⚠️ Health check failed for ${service} (status: ${status}). Attempting to heal/recreate..."
                            // This command will now have the correct environment variables loaded.
                            sh "set -a; source ${env.WORKSPACE}/versions.env; set +a; docker compose up -d --no-deps --force-recreate ${service}"
                        } else {
                            echo "✅ Health check passed for ${service}."
                        }
                    }
                }
            }
        }

        // -------------------------------
        // Stage 7: Commit Version File (Runs for ALL relevant triggers)
        // -------------------------------
        stage('Commit Version Update') {
            when {
                anyOf {
                    triggeredBy 'SCMTrigger'
                    triggeredBy 'TimerTrigger'
                    triggeredBy 'UserIdCause'
                }
            }
            steps {
                script {
                    def gitStatus = sh(script: 'git status --porcelain versions.yml', returnStdout: true).trim()
                    if (gitStatus) {
                        echo "versions.yml has changed. Committing updates..."
                        withCredentials([usernamePassword(credentialsId: GITHUB_CREDS, usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
                            sh """
                                git config --global user.email "jenkins@ci.com"
                                git config --global user.name "Jenkins CI"
                                git add versions.yml
                                git commit -m "ci: Update service versions [skip ci]"
                                git push https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/Rtx-boii/vcct.git HEAD:vcct-setup
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
        // This block is the pipeline's "emergency procedure". It runs if any stage fails.
        failure {
            script {
                echo "A failure occurred. Checking for services that need to be rolled back."
                def currentVersions = readYaml file: 'versions.yml'
                def oldVersionsContent = sh(script: "git show ${GIT_PREVIOUS_COMMIT}:versions.yml", returnStdout: true).trim()
                def oldVersions = readYaml text: oldVersionsContent
                
                oldVersions.keySet().each { service ->
                    if (currentVersions.get(service) != oldVersions.get(service)) {
                        echo "Rolling back ${service} from version ${currentVersions.get(service, 'N/A')} to ${oldVersions.get(service, 'N/A')}."
                        // Redeploy the service using the old, stable version number.
                        sh "export ${service.replace('-', '_').toUpperCase()}_VERSION=${oldVersions[service]}; docker compose up -d --no-deps --force-recreate ${service}"
                        // Update the version in the workspace to reflect the rollback.
                        currentVersions[service] = oldVersions[service]
                    }
                }
                // Write the corrected file, so the final 'Commit' stage can push the rollback to Git.
                writeYaml file: 'versions.yml', data: currentVersions, overwrite: true
                echo "Workspace versions.yml has been updated to reflect the rollback."
            }
        }
        // This block always runs to clean up the workspace.
        always {
            sh 'rm -f build-services.txt restart-services.txt versions.env'
        }
    }
}
