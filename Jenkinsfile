pipeline {
    agent any

    environment {
        DOCKER_USER  = "nilessh"
        DOCKER_PASS  = credentials('docker-hub-creds')
        GITHUB_CREDS = credentials('github-creds')
        WORKSPACE_DIR = "${env.WORKSPACE}"
        SERVICES = ['dhcp-server', 'dns-server', 'squid-proxy']
    }

    triggers {
        // Cron to run health check every 10 minutes
        cron('H/10 * * * *')
    }

    stages {
        stage('Checkout SCM') {
            steps {
                checkout([$class: 'GitSCM',
                    branches: [[name: '*/vcct-setup']],
                    doGenerateSubmoduleConfigurations: false,
                    extensions: [],
                    userRemoteConfigs: [[
                        credentialsId: 'github-creds',
                        url: 'https://github.com/Rtx-boii/vcct.git'
                    ]]
                ])
            }
        }

        stage('Detect Changes') {
            when {
                not { triggeredBy 'TimerTrigger' } // Skip on cron
            }
            steps {
                script {
                    CHANGED_FILES = sh(
                        script: "git diff-tree --no-commit-id --name-only -r HEAD~1 HEAD",
                        returnStdout: true
                    ).trim().split("\n")
                    echo "Changed files: ${CHANGED_FILES}"

                    BUILD_SERVICES = []
                    RESTART_SERVICES = []

                    SERVICES.each { svc ->
                        def dockerfileChanged = CHANGED_FILES.any { it.startsWith("${svc}/Dockerfile") }
                        def entrypointChanged = CHANGED_FILES.any { it.startsWith("${svc}/entrypoint") || it.startsWith("${svc}/start-squid.sh") }

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
                allOf {
                    not { triggeredBy 'TimerTrigger' }
                    expression { return fileExists('build-services.txt') && readFile('build-services.txt').trim() }
                }
            }
            steps {
                script {
                    // Read versions.yml
                    def versions = readYaml file: 'versions.yml'

                    sh """
                    set -a
                    [ -f \$WORKSPACE/versions.env ] || echo "DHCP_SERVER_VERSION=1\\nDNS_SERVER_VERSION=1\\nSQUID_PROXY_VERSION=1" > \$WORKSPACE/versions.env
                    . \$WORKSPACE/versions.env

                    for svc in \$(cat build-services.txt); do
                        # Increment version in env
                        version_var="\${svc.replace('-', '_').toUpperCase()}_VERSION"
                        version_val=\$((\${!version_var}+1))
                        export \$version_var=\$version_val

                        echo "Building \$svc with version \$version_val"
                        docker build -t nilessh/\$svc:\$version_val \$WORKSPACE/\$svc
                        docker push nilessh/\$svc:\$version_val

                        # Update versions.yml file
                        yq e -i ".\"${svc}\" = \$version_val" \$WORKSPACE/versions.yml
                    done

                    # Update versions.env as well
                    env | grep _VERSION= | grep -E 'DHCP|DNS|SQUID' > \$WORKSPACE/versions.env
                    """
                }
            }
        }

        stage('Deploy Services') {
            steps {
                script {
                    sh """
                    set -a
                    [ -f \$WORKSPACE/versions.env ] || echo "DHCP_SERVER_VERSION=1\\nDNS_SERVER_VERSION=1\\nSQUID_PROXY_VERSION=1" > \$WORKSPACE/versions.env
                    . \$WORKSPACE/versions.env

                    # Recreate containers for built images
                    if [ -f build-services.txt ]; then
                        for svc in \$(cat build-services.txt); do
                            docker compose up -d --no-deps --force-recreate \$svc
                        done
                    fi

                    # Recreate containers for other changed files
                    if [ -f restart-services.txt ]; then
                        for svc in \$(cat restart-services.txt); do
                            docker compose up -d --no-deps --force-recreate \$svc
                        done
                    fi
                    """
                }
            }
        }

        stage('Health Check') {
            steps {
                script {
                    sh """
                    for svc in dhcp-server dns-server squid-proxy; do
                        status=\$(docker inspect --format='{{.State.Health.Status}}' \$svc 2>/dev/null || echo 'unknown')
                        echo "\$svc health: \$status"
                        if [ "\$status" != "healthy" ]; then
                            echo "Warning: \$svc is not healthy!"
                        fi
                    done
                    """
                }
            }
        }

        stage('Commit Version Updates') {
            when {
                allOf {
                    not { triggeredBy 'TimerTrigger' }
                    expression { return fileExists('build-services.txt') && readFile('build-services.txt').trim() }
                }
            }
            steps {
                script {
                    sh """
                    git config user.email "jenkins@vcct.com"
                    git config user.name "Jenkins CI"
                    git add versions.yml
                    git commit -m "Update service versions after build"
                    git push origin vcct-setup
                    """
                }
            }
        }
    }

    post {
        always {
            sh 'rm -f build-services.txt restart-services.txt'
        }
    }
}
