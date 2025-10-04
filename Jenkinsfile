pipeline {
    agent any

    environment {
        REPO_URL = "https://github.com/Rtx-boii/vcct.git"
        BRANCH   = "vcct-setup"
        VERSION_FILE = "version.yml"
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: "${BRANCH}", 
                    url: "${REPO_URL}", 
                    credentialsId: "github-creds"
            }
        }

        stage('Docker Login') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'docker-hub-creds', 
                    usernameVariable: 'DOCKER_USER', 
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh 'docker logout || true'
                    sh 'echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin'
                }
            }
        }

        stage('Detect Changes') {
            steps {
                script {
                    def changedFiles = sh(script: "git diff --name-only HEAD~1 HEAD", returnStdout: true).trim().split("\\n")
                    echo "Changed files: ${changedFiles}"

                    env.TARGET_SERVICES = ""
                    env.REBUILD = "false"
                    env.COMPOSE_CHANGED = "false"
                    env.VERSION_CHANGED = ""

                    for (file in changedFiles) {
                        if (file == "docker-compose.yml") {
                            env.COMPOSE_CHANGED = "true"
                        } else if (file == VERSION_FILE) {
                            def services = ['dhcp-server','dns-server','squid-proxy']
                            for (svc in services) {
                                def oldVersion = sh(script: "git show HEAD~1:${VERSION_FILE} | yq e '.\"${svc}\"' -", returnStdout: true).trim().toInteger()
                                def newVersion = sh(script: "yq e '.\"${svc}\"' ${VERSION_FILE}", returnStdout: true).trim().toInteger()
                                if (newVersion < 1) {
                                    echo "Version for ${svc} below minimum, forcing to 1."
                                    sh "yq e -i '.\"${svc}\" = 1' ${VERSION_FILE}"
                                    newVersion = 1
                                }
                                if (oldVersion != newVersion) {
                                    echo "Detected version change for ${svc}: ${oldVersion} -> ${newVersion}"
                                    env.VERSION_CHANGED += "${svc} "
                                }
                            }
                        } else if (file.endsWith("Dockerfile") || file.endsWith("entrypoint.sh")) {
                            env.REBUILD = "true"
                            def svc = file.split("/")[0]
                            env.TARGET_SERVICES += "${svc} "
                        } else if (file.startsWith("dhcp-server/") || file.startsWith("dns-server/") || file.startsWith("squid-proxy/")) {
                            def svc = file.split("/")[0]
                            env.TARGET_SERVICES += "${svc} "
                        }
                    }
                }
            }
        }

        stage('Deploy Compose Change') {
            when { expression { return env.COMPOSE_CHANGED == "true" } }
            steps {
                script {
                    echo "docker-compose.yml changed, redeploying all services..."
                    sh 'docker compose down'
                    sh '''
                        DHCP_SERVER_VERSION=$(yq e '.\"dhcp-server\"' version.yml)
                        DNS_SERVER_VERSION=$(yq e '.\"dns-server\"' version.yml)
                        SQUID_PROXY_VERSION=$(yq e '.\"squid-proxy\"' version.yml)
                        docker compose up -d
                    '''
                }
            }
        }

        stage('Restart Version Changed Services') {
            when { expression { return env.VERSION_CHANGED?.trim() } }
            steps {
                script {
                    def services = env.VERSION_CHANGED.trim().split(" ")
                    for (svc in services) {
                        echo "Restarting ${svc} due to manual version change..."
                        sh "docker compose restart ${svc}"
                    }
                }
            }
        }

        stage('Build, Push & Deploy') {
            when { expression { return env.REBUILD == "true" } }
            steps {
                script {
                    def services = env.TARGET_SERVICES.trim().split(" ")
                    for (svc in services) {
                        // Only rebuild if Dockerfile or entrypoint.sh changed
                        def rebuildFileChanged = sh(
                            script: "git diff --name-only HEAD~1 HEAD | grep -E '^${svc}/(Dockerfile|entrypoint.sh)' || true",
                            returnStdout: true
                        ).trim()

                        if (rebuildFileChanged) {
                            echo "Building ${svc} because Dockerfile/entrypoint.sh changed..."
                            def version = sh(script: "yq e '.\"${svc}\"' ${VERSION_FILE}", returnStdout: true).trim().toInteger()
                            if (version < 1) { version = 1; sh "yq e -i '.\"${svc}\" = 1' ${VERSION_FILE}" }

                            sh "docker build -t $DOCKER_USER/${svc}:${version} ${svc}"
                            echo "Pushing ${svc}:${version} to Docker Hub..."
                            sh "docker push $DOCKER_USER/${svc}:${version}"
                            echo "Deploying ${svc}:${version} from Docker Hub..."
                            sh "docker pull $DOCKER_USER/${svc}:${version}"
                            sh "docker compose up -d --force-recreate --no-deps ${svc}"
                        } else {
                            echo "No Dockerfile/entrypoint.sh change for ${svc}, skipping rebuild."
                        }
                    }
                }
            }
        }

        stage('Health Check & Rollback') {
            when { expression { return env.TARGET_SERVICES?.trim() || env.VERSION_CHANGED?.trim() || env.COMPOSE_CHANGED == "true" } }
            steps {
                script {
                    def services = (env.TARGET_SERVICES + " " + env.VERSION_CHANGED).trim().split(" ").unique()
                    for (svc in services) {
                        echo "Waiting 60s for ${svc} to stabilize..."
                        sleep 60
                        def containerId = sh(script: "docker compose ps -q ${svc}", returnStdout: true).trim()
                        def healthy = sh(script: "docker inspect --format='{{.State.Health.Status}}' ${containerId} || echo 'unknown'", returnStdout: true).trim()
                        echo "${svc} health: ${healthy}"

                        if (healthy != "healthy" && healthy != "running") {
                            echo "Rollback triggered for ${svc}"
                            def currentVersion = sh(script: "yq e '.\"${svc}\"' ${VERSION_FILE}", returnStdout: true).trim().toInteger()
                            def prevVersion = currentVersion - 1
                            if (prevVersion < 1) { prevVersion = currentVersion }
                            sh "docker pull $DOCKER_USER/${svc}:${prevVersion} || true"
                            sh "docker compose down ${svc} || true"
                            sh "docker run -d --name ${svc} $DOCKER_USER/${svc}:${prevVersion}"
                            sh "yq e -i '.\"${svc}\" = ${prevVersion}' ${VERSION_FILE}"
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
