pipeline {
    agent any

    environment {
        DOCKER_USER  = "nilessh"
        DOCKER_PASS  = credentials('docker-hub-creds')
        GITHUB_CREDS = credentials('github-creds')
        ALL_SERVICES = "dhcp-server dns-server squid-proxy"
    }

    options {
        skipDefaultCheckout()
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    stages {

        stage('Checkout SCM') {
            steps {
                checkout scm
            }
        }

        stage('Detect Changes') {
            steps {
                script {
                    // Get the last two commits
                    def prev = sh(script: "git rev-parse HEAD~1", returnStdout: true).trim()
                    def curr = sh(script: "git rev-parse HEAD", returnStdout: true).trim()

                    // Changed files
                    def changedFiles = sh(script: "git diff-tree --no-commit-id --name-only -r ${prev} ${curr}", returnStdout: true).trim().split("\n")
                    echo "Changed files: ${changedFiles}"

                    // Define critical build files for each service
                    def buildFiles = [
                        'dhcp-server': ['Dockerfile', 'Dockerfile.sh'],
                        'dns-server': ['Dockerfile', 'entrypoint.sh'],
                        'squid-proxy': ['Dockerfile', 'start-squid.sh']
                    ]

                    def servicesToBuild = []
                    def servicesToRestart = []

                    ALL_SERVICES.split().each { service ->
                        def changedBuildFiles = changedFiles.findAll { it.startsWith("${service}/") && buildFiles[service].any { f -> it.endsWith(f) } }
                        if (changedBuildFiles) {
                            servicesToBuild << service
                        } else if (changedFiles.any { it.startsWith("${service}/") }) {
                            servicesToRestart << service
                        }
                    }

                    // Save for later stages
                    writeFile file: 'build-services.txt', text: servicesToBuild.join("\n")
                    writeFile file: 'restart-services.txt', text: servicesToRestart.join("\n")
                    echo "Services to Build: ${servicesToBuild}"
                    echo "Services to Restart: ${servicesToRestart}"
                }
            }
        }

        stage('Build and Push Images') {
            when {
                expression { return readFile('build-services.txt').trim() != "" }
            }
            steps {
                script {
                    def servicesToBuild = readFile('build-services.txt').trim().split("\n")
                    def versions = [:]

                    // Load previous versions
                    if (fileExists('versions.yml')) {
                        versions = readYaml(file: 'versions.yml')
                    }

                    servicesToBuild.each { service ->
                        // Increment version
                        versions[service] = (versions[service] ?: 0) + 1
                        def version = versions[service]

                        echo "Building ${service}:${version}"
                        sh """
                        docker build -t ${DOCKER_USER}/${service}:${version} ./${service}
                        docker login -u ${DOCKER_USER} -p ${DOCKER_PASS}
                        docker push ${DOCKER_USER}/${service}:${version}
                        """
                    }

                    // Save updated versions
                    writeYaml file: 'versions.yml', data: versions
                    def envContent = versions.collect { k,v -> "${k.toUpperCase().replace('-','_')}_VERSION=${v}" }.join("\n")
                    writeFile file: 'versions.env', text: envContent
                }
            }
        }

        stage('Deploy Services') {
            steps {
                script {
                    // Load versions
                    if (fileExists('versions.env')) {
                        sh "set -a; . ./versions.env; set +a"
                    }

                    def restartServices = readFile('restart-services.txt').trim().split("\n")
                    restartServices.each { service ->
                        echo "Deploying ${service}"
                        sh "docker compose up -d --no-deps --force-recreate ${service}"
                    }

                    def buildServices = readFile('build-services.txt').trim().split("\n")
                    buildServices.each { service ->
                        echo "Deploying ${service}"
                        sh "docker compose up -d --no-deps --force-recreate ${service}"
                    }
                }
            }
        }

        stage('Post-Deployment Health Check') {
            steps {
                script {
                    def services = ALL_SERVICES.split()
                    services.each { service ->
                        echo "Waiting for ${service}..."
                        sleep 20
                        def status = sh(script: "docker inspect --format='{{.State.Health.Status}}' ${service}", returnStdout: true).trim()
                        if (status != "healthy") {
                            error "Health check failed for ${service} (status: ${status})"
                        }
                        echo "${service} is healthy."
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
                    ALL_SERVICES.split().each { service ->
                        echo "Monitoring ${service}..."
                        def status = sh(script: "docker inspect --format='{{.State.Health.Status}}' ${service}", returnStdout: true).trim()
                        if (status != "healthy") {
                            echo "${service} unhealthy! Attempting restart..."
                            sh "docker compose up -d --no-deps --force-recreate ${service}"
                        } else {
                            echo "${service} is healthy."
                        }
                    }
                }
            }
        }

        stage('Commit Version Updates') {
            when {
                expression { return readFile('build-services.txt').trim() != "" }
            }
            steps {
                script {
                    sh """
                    git config user.name 'Jenkins'
                    git config user.email 'jenkins@local'
                    git add versions.yml
                    git commit -m 'Update service versions [Jenkins]'
                    git push origin HEAD
                    """
                }
            }
        }
    }

    post {
        always {
            sh 'rm -f build-services.txt restart-services.txt versions.env'
        }
        failure {
            script {
                echo "Failure detected. Attempting rollback..."
                if (fileExists('versions.yml')) {
                    def versions = readYaml(file: 'versions.yml')
                    echo "Previous versions: ${versions}"
                }
            }
        }
    }
}
