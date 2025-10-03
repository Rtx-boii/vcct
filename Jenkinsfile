pipeline {
    agent any

    environment {
        DOCKER_USER  = "nilessh"
        DOCKER_PASS  = credentials('docker-hub-creds')
        GITHUB_CREDS = credentials('github-creds')
    }

    triggers {
        // Health check every 10 minutes
        cron('H/10 * * * *')
    }

    stages {
        stage('Checkout SCM') {
            steps {
                checkout([$class: 'GitSCM',
                    branches: [[name: '*/vcct-setup']],
                    doGenerateSubmoduleConfigurations: false,
                    extensions: [[$class: 'CloneOption', shallow: true, depth: 2]],
                    userRemoteConfigs: [[
                        credentialsId: 'github-creds',
                        url: 'https://github.com/Rtx-boii/vcct.git'
                    ]]
                ])
            }
        }

        stage('Detect Changes') {
            when { not { triggeredBy 'TimerTrigger' } }
            steps {
                script {
                    def SERVICES = ['dhcp-server', 'dns-server', 'squid-proxy']

                    // Changed files between last two commits (safe for first run)
                    def CHANGED_FILES = sh(
                        script: "git diff-tree --no-commit-id --name-only -r HEAD~1 HEAD || true",
                        returnStdout: true
                    ).trim().split("\n")
                    echo "Changed files: ${CHANGED_FILES}"

                    def BUILD_SERVICES = []
                    def RESTART_SERVICES = []

                    SERVICES.each { svc ->
                        def dockerfileChanged = CHANGED_FILES.any { it == "${svc}/Dockerfile" }
                        def entrypointChanged = CHANGED_FILES.any {
                            it.startsWith("${svc}/entrypoint") || it.startsWith("${svc}/start-squid.sh")
                        }

                        if (dockerfileChanged || entrypointChanged) {
                            BUILD_SERVICES.add(svc)
                        } else if (CHANGED_FILES.any { it.startsWith("${svc}/") }) {
                            RESTART_SERVICES.add(svc)
                        }
                    }

                    echo "Services to Build: ${BUILD_SERVICES}"
                    echo "Services to Restart: ${RESTART_SERVICES}"

                    writeFile file: 'build-services.txt', text: BUILD_SERVICES.join('\n')
                    writeFile file: 'restart-services.txt', text: RESTART_SERVICES.join('\n')
                }
            }
        }

        stage('Build and Push Images') {
            when {
                expression { return fileExists('build-services.txt') && readFile('build-services.txt').trim() != '' }
            }
            steps {
                script {
                    sh """
                        set -a
                        [ -f \$WORKSPACE/versions.env ] || touch \$WORKSPACE/versions.env
                        . \$WORKSPACE/versions.env
                    """

                    // Docker login
                    sh "echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin"

                    def buildServices = readFile('build-services.txt').trim().split("\n")
                    buildServices.each { svc ->
                        def versionVar = svc.toUpperCase().replace('-', '_') + "_VERSION"
                        def version = sh(
                            script: "grep -E '^${versionVar}=' \$WORKSPACE/versions.env | cut -d '=' -f2 || true",
                            returnStdout: true
                        ).trim()

                        if (version.isInteger()) {
                            version = version.toInteger() + 1
                        } else {
                            version = 1
                        }

                        sh "docker build -t ${DOCKER_USER}/${svc}:${version} ./${svc}"
                        sh "docker push ${DOCKER_USER}/${svc}:${version}"

                        // Update env file
                        sh "grep -v '^${versionVar}=' \$WORKSPACE/versions.env > \$WORKSPACE/versions.env.tmp || true"
                        sh "echo ${versionVar}=${version} >> \$WORKSPACE/versions.env.tmp"
                        sh "mv \$WORKSPACE/versions.env.tmp \$WORKSPACE/versions.env"
                    }
                }
            }
        }

        stage('Deploy Services') {
            steps {
                script {
                    sh """
                        set -a
                        [ -f \$WORKSPACE/versions.env ] || touch \$WORKSPACE/versions.env
                        . \$WORKSPACE/versions.env
                    """

                    def restartServices = fileExists('restart-services.txt') ? readFile('restart-services.txt').trim().split("\n") : []
                    def buildServices   = fileExists('build-services.txt') ? readFile('build-services.txt').trim().split("\n") : []
                    def deployServices  = (restartServices + buildServices).findAll { it?.trim() }.unique()

                    if (deployServices && deployServices.size() > 0) {
                        deployServices.each { svc ->
                            sh "docker compose up -d --no-deps --force-recreate ${svc}"
                        }
                    } else {
                        echo "No services to deploy."
                    }
                }
            }
        }

        stage('Update versions.yml in repo') {
            when { not { triggeredBy 'TimerTrigger' } }
            steps {
                script {
                    if (fileExists('versions.env')) {
                        def versionsMap = [:]
                        def content = readFile('versions.env').trim().split("\n")
                        content.each { line ->
                            def parts = line.split('=')
                            if (parts.size() == 2) {
                                versionsMap[parts[0]] = parts[1]
                            }
                        }

                        // Safely overwrite versions.yml
                        if (fileExists('versions.yml')) {
                            sh "rm -f versions.yml"
                        }
                        writeYaml file: 'versions.yml', data: versionsMap

                        sh """
                            git config user.email "jenkins@vcct.com"
                            git config user.name "Jenkins"
                            git add versions.yml
                            git commit -m "Update versions.yml by pipeline" || echo "No changes to commit"
                            git push origin vcct-setup
                        """
                    }
                }
            }
        }

        stage('Health Monitoring (TimerTrigger)') {
            when { triggeredBy 'TimerTrigger' }
            steps {
                script {
                    sh "docker ps -a"
                    sh "docker compose ps"
                }
            }
        }
    }

    post {
        always {
            sh "rm -f build-services.txt restart-services.txt"
            archiveArtifacts artifacts: 'versions.env', onlyIfSuccessful: true
        }
        failure {
            echo "Pipeline failed. Rollback or manual intervention may be required."
        }
    }
}
