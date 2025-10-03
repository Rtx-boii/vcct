pipeline {
    agent any

    environment {
        DOCKER_USER  = "nilessh"
        DOCKER_PASS  = credentials('docker-hub-creds')
        GITHUB_CREDS = credentials('github-creds')
        WORKSPACE    = "${env.WORKSPACE}"
    }

    options {
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    triggers {
        // Cron triggers only for health check
        cron('H/10 * * * *')
    }

    stages {

        stage('Checkout SCM') {
            when {
                expression { !currentBuild.getBuildCauses('hudson.triggers.TimerTrigger$TimerTriggerCause') }
            }
            steps {
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: '*/vcct-setup']],
                    userRemoteConfigs: [[
                        url: 'https://github.com/Rtx-boii/vcct.git',
                        credentialsId: 'github-creds'
                    ]]
                ])
            }
        }

        stage('Detect Changes') {
            when {
                expression { !currentBuild.getBuildCauses('hudson.triggers.TimerTrigger$TimerTriggerCause') }
            }
            steps {
                script {
                    def prevCommit = sh(script: "git rev-parse HEAD~1", returnStdout: true).trim()
                    def currCommit = sh(script: "git rev-parse HEAD", returnStdout: true).trim()
                    def changedFiles = sh(
                        script: "git diff-tree --no-commit-id --name-only -r ${prevCommit} ${currCommit}",
                        returnStdout: true
                    ).trim().split("\n")

                    echo "Changed files: ${changedFiles}"

                    def buildServices = []
                    def restartServices = []

                    changedFiles.each { file ->
                        if (file.startsWith("dhcp-server/")) {
                            if (file.endsWith("Dockerfile") || file.endsWith("entrypoint.sh")) {
                                buildServices << "dhcp-server"
                            } else {
                                restartServices << "dhcp-server"
                            }
                        } else if (file.startsWith("dns-server/")) {
                            if (file.endsWith("Dockerfile") || file.endsWith("entrypoint.sh")) {
                                buildServices << "dns-server"
                            } else {
                                restartServices << "dns-server"
                            }
                        } else if (file.startsWith("squid-proxy/")) {
                            if (file.endsWith("Dockerfile") || file.endsWith("start-squid.sh")) {
                                buildServices << "squid-proxy"
                            } else {
                                restartServices << "squid-proxy"
                            }
                        }
                    }

                    buildServices = buildServices.unique()
                    restartServices = restartServices.unique() - buildServices

                    writeFile file: 'build-services.txt', text: buildServices.join("\n")
                    writeFile file: 'restart-services.txt', text: restartServices.join("\n")

                    echo "Services to Build: ${buildServices}"
                    echo "Services to Restart: ${restartServices}"
                }
            }
        }

        stage('Build and Push Images') {
            when {
                allOf {
                    expression { !currentBuild.getBuildCauses('hudson.triggers.TimerTrigger$TimerTriggerCause') }
                    expression { fileExists('build-services.txt') && readFile('build-services.txt').trim() }
                }
            }
            steps {
                script {
                    def buildServices = readFile('build-services.txt').trim().split("\n")
                    buildServices.each { service ->
                        sh """
                            cd ${service}
                            docker build -t ${DOCKER_USER}/${service}:latest .
                            docker push ${DOCKER_USER}/${service}:latest
                        """
                    }
                }
            }
        }

        stage('Update Versions') {
            when {
                allOf {
                    expression { !currentBuild.getBuildCauses('hudson.triggers.TimerTrigger$TimerTriggerCause') }
                    expression { fileExists('build-services.txt') && readFile('build-services.txt').trim() }
                }
            }
            steps {
                script {
                    def buildServices = readFile('build-services.txt').trim().split("\n")
                    def prevVersions = [:]

                    if (fileExists('versions.yml')) {
                        prevVersions = readYaml file: 'versions.yml'
                    }

                    def envContent = ""
                    buildServices.each { service ->
                        def prev = prevVersions.get(service) ?: 0
                        def newVersion = prev.toInteger() + 1
                        prevVersions[service] = newVersion
                        envContent += "${service.toUpperCase().replace('-','_')}_VERSION=${newVersion}\n"
                    }

                    writeFile file: 'versions.env', text: envContent
                    writeYaml file: 'versions.yml', data: prevVersions
                }
            }
        }

        stage('Deploy Services') {
            when {
                expression { !currentBuild.getBuildCauses('hudson.triggers.TimerTrigger$TimerTriggerCause') }
            }
            steps {
                script {
                    sh "set -a && . ${WORKSPACE}/versions.env && set +a"

                    if (fileExists('build-services.txt') && readFile('build-services.txt').trim()) {
                        def buildServices = readFile('build-services.txt').trim().split("\n")
                        buildServices.each { service ->
                            sh "docker compose up -d --no-deps --force-recreate ${service}"
                        }
                    }

                    if (fileExists('restart-services.txt') && readFile('restart-services.txt').trim()) {
                        def restartServices = readFile('restart-services.txt').trim().split("\n")
                        restartServices.each { service ->
                            sh "docker compose up -d --no-deps --force-recreate ${service}"
                        }
                    }
                }
            }
        }

        stage('Health Check') {
            steps {
                script {
                    def services = ['dhcp-server','dns-server','squid-proxy']
                    services.each { service ->
                        def status = sh(
                            script: "docker inspect --format='{{.State.Health.Status}}' ${service}",
                            returnStdout: true
                        ).trim()
                        echo "${service} health status: ${status}"
                        if (status != 'healthy') {
                            error("${service} is not healthy!")
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            sh "rm -f build-services.txt restart-services.txt versions.env"
        }
        failure {
            script {
                echo "Failure detected. Attempting rollback..."
                if (fileExists('versions.yml')) {
                    def prevVersions = readYaml file: 'versions.yml'
                    echo "Previous versions: ${prevVersions}"
                }
            }
        }
    }
}
