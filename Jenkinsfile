pipeline {
  agent { label 'jenkins' }

  environment {
    IMAGE_REGISTRY   = "hoangvu42"
    SONARQUBE_ENV    = "sonarqube-server"
    GITOPS_REPO_URL  = "https://github.com/v4224/dacn-gitops.git"
    ALL_SERVICES     = "api-gateway,identity-service,profile-service,notification-service,post-service"
  }

  options {
    skipDefaultCheckout(true)
    timestamps()
  }

  stages {
    stage('Checkout Source') {
      steps {
        checkout scm
        script {
          def currentBranch = env.BRANCH_NAME
          env.BRANCH = currentBranch
          echo "=== Checkout done ==="
          echo "Current Branch => ${currentBranch}"
        }
      }
    }

    stage('Set Image Tag') {
      steps {
        script {
          def branch = env.BRANCH ?: "develop"

          if (branch == 'deploy') {
            env.IMAGE_TAG = "prod-${env.BUILD_ID}"
          } else {
            def commitHash = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
            env.IMAGE_TAG = "${branch}-${commitHash}"
            env.RUN_SONAR = "true"
          }

          echo "Image tag: ${env.IMAGE_TAG}"
          echo "Run SonarQube? => ${env.RUN_SONAR}"
        }
      }
    }

    stage('Detect Changed Services') {
      steps {
        script {
          def all = ALL_SERVICES.split(',')

          if (env.BRANCH == 'deploy') {
            env.CHANGED_SERVICES = all.join(',')
            echo "Branch 'deploy' → build all services"
          } else {
            sh "git fetch origin ${env.BRANCH}"
            def diffRaw = sh(returnStdout: true, script: "git diff --name-only origin/${env.BRANCH}").trim()

            if (diffRaw) {
              def changedDirs = diffRaw.split('\n').collect { it.split('/')[0] }.unique()
              def matchedServices = changedDirs.findAll { all.contains(it) }
              env.CHANGED_SERVICES = matchedServices ? matchedServices.join(',') : all.join(',')
            } else {
              echo "No files changed compared to origin/${env.BRANCH}. Build all."
              env.CHANGED_SERVICES = all.join(',')
            }
          }

          echo "List of services to build: ${env.CHANGED_SERVICES}"
        }
      }
    }

    stage('SonarQube Analysis') {
      when {
        expression {
          return (env.RUN_SONAR == 'true') && (env.CHANGED_SERVICES?.trim())
        }
      }
      steps {
        script {
          def scannerHome = tool 'SonarScanner'
          def services = env.CHANGED_SERVICES.split(',')
          def sonarTasks = [:]

          services.each { svc ->
            sonarTasks[svc] = {
              dir(svc) {
                withSonarQubeEnv("${SONARQUBE_ENV}") {
                  sh "${scannerHome}/bin/sonar-scanner \
                      -Dsonar.projectKey=${svc} \
                      -Dsonar.sources=. \
                      -Dsonar.java.binaries=."
                }
              }
            }
          }
          parallel sonarTasks
        }
      }
      post {
        success {
          script {
            if (env.RUN_SONAR == 'true') {
              timeout(time: 15, unit: 'MINUTES') {
                waitForQualityGate(abortPipeline: true)
              }
            }
          }
        }
        failure {
          echo "An error has occurred during the SonarQube analysis process."
        }
      }
    }

    stage('Build & Scan Docker Images') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'dockerhub-token',
          usernameVariable: 'DOCKER_USER',
          passwordVariable: 'DOCKER_PASS'
        )]) {
          script {
            sh '''
              echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin
            '''

            sh """
              mkdir -p ${env.WORKSPACE}/.trivy-cache
              mkdir -p ${env.WORKSPACE}/trivy-reports
            """

            def services = env.CHANGED_SERVICES.split(',')
            def buildTasks = [:]

            services.each { svc ->
              buildTasks[svc] = {
                dir(svc) {
                  sh "docker build -t ${IMAGE_REGISTRY}/${svc}:${env.IMAGE_TAG} ."

                  sh """
                    docker run --rm \
                      -v /var/run/docker.sock:/var/run/docker.sock \
                      -v ${env.WORKSPACE}/.trivy-cache:/root/.cache/trivy \
                      -v ${env.WORKSPACE}/trivy-reports:/reports \
                      aquasec/trivy image \
                      --cache-dir /root/.cache/trivy \
                      --scanners vuln \
                      --timeout 15m \
                      --format template \
                      --template @contrib/html.tpl \
                      --output /reports/${svc}-trivy-scan-report.html \
                      ${IMAGE_REGISTRY}/${svc}:${env.IMAGE_TAG} || true
                  """
                  echo "→ Trivy scan for ${svc} completed (report: trivy-reports/${svc}-trivy-scan-report.html)"
                }
              }
            }
            parallel buildTasks
          }
        }
      }
    }

    stage('Push Images') {
      steps {
        script {
          def services = env.CHANGED_SERVICES.split(',')
          def pushTasks = [:]

          services.each { svc ->
            pushTasks[svc] = {
              sh "docker push ${IMAGE_REGISTRY}/${svc}:${env.IMAGE_TAG}"
            }
          }
          parallel pushTasks
        }
      }
    }

    stage('Update GitOps Manifests') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'github-token',
          usernameVariable: 'GIT_USER',
          passwordVariable: 'GIT_PASS'
        )]) {
          script {
            sh '''
              if [ -d "gitops" ]; then rm -rf gitops; fi
              git clone https://$GIT_USER:$GIT_PASS@github.com/v4224/dacn-gitops.git gitops
            '''

            dir('gitops') {
              def exists = sh(returnStdout: true,
                              script: "git ls-remote --heads origin ${env.BRANCH} || true").trim()
              if (!exists) {
                sh "git checkout -b ${env.BRANCH}"
              } else {
                sh "git checkout ${env.BRANCH}"
              }

              def pathPrefix = (env.BRANCH == 'deploy') ? 'prod' : 'dev'
              def services = env.CHANGED_SERVICES.split(',')

              services.each { svc ->
                def file = "app/${svc}/${svc}-deployment.yaml"
                sh """
                  sed -i 's#image: .*/${svc}:.*#image: ${IMAGE_REGISTRY}/${svc}:${env.IMAGE_TAG}#' ${file}
                """
              }

              sh '''
                git config user.name "jenkins-ci"
                git config user.email "[email protected]"
                git add .
                git commit -m "Update image tags to ${IMAGE_TAG} [ci skip]" || echo "No changes to commit"
                git push https://$GIT_USER:$GIT_PASS@github.com/v4224/dacn-gitops.git ${BRANCH}:${BRANCH}
              '''
            }
          }
        }
      }
    }
  }
}
