pipeline {
  agent { label 'jenkins' }

  environment {
    REGISTRY_CRED    = credentials('docker-hub')
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
        // Dùng Multibranch Pipeline, Jenkins sẽ cung cấp biến BRANCH_NAME
        checkout scm

        script {
          // Lấy branch hiện tại do Jenkins cung cấp
          def currentBranch = env.BRANCH_NAME
          // Kiểm tra nếu là build vì tag? Theo mặc định Multibranch không build tag,
          // nên nếu bạn muốn build tag, cần thêm cấu hình. Ở đây giả sử branch chỉ là develop hoặc deploy.
          env.TAG_NAME = ""
          env.BRANCH   = currentBranch
          echo "=== Checkout done! ==="
          echo "Current Branch => ${currentBranch}"
        }
      }
    }

    stage('Set Image Tag') {
      steps {
        script {
          def branch = env.BRANCH   ?: "develop"
          // Chúng ta coi mọi branch không phải là tag → gắn prefix develop-
          // Nếu bạn muốn sản phẩm production (deploy branch), có thể thêm điều kiện
          if (branch == 'deploy') {
            env.IMAGE_TAG = "prod-${env.BUILD_ID}"
            env.RUN_SONAR  = "false" // không chạy Sonar cho branch deploy (tuỳ nhu cầu)
          } else {
            // branch develop hoặc các feature branch khác
            def commitHash = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
            env.IMAGE_TAG = "${branch}-${commitHash}"
            env.RUN_SONAR  = "true"
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
            // build tất cả services khi deploy sang production
            env.CHANGED_SERVICES = all.join(',')
            echo "Branch 'deploy' → build all services"
          } else {
            // So sánh với origin/develop
            sh "git fetch origin ${env.BRANCH}"
            def diffRaw = sh(returnStdout: true, script: "git diff --name-only origin/${env.BRANCH}").trim()
            if (diffRaw) {
              def changedDirs = diffRaw.split('\n').collect { it.split('/')[0] }.unique()
              def intersect = changedDirs.intersect(all as List)
              if (intersect.size() > 0) {
                env.CHANGED_SERVICES = intersect.join(',')
              } else {
                echo "No changes found in nay service folders. Build all."
                env.CHANGED_SERVICES = all.join(',')
              }
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
            timeout(time: 15, unit: 'MINUTES') {
              waitForQualityGate(abortPipeline: true)
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
        script {
          // 1. Login Docker Hub
          sh "echo ${REGISTRY_CRED_PSW} | docker login -u ${REGISTRY_CRED_USR} --password-stdin"

          // 2. Tạo thư mục cache và reports
          sh """
            mkdir -p ${env.WORKSPACE}/.trivy-cache
            mkdir -p ${env.WORKSPACE}/trivy-reports
          """

          def services = env.CHANGED_SERVICES.split(',')
          def buildTasks = [:]

          services.each { svc ->
            buildTasks[svc] = {
              dir(svc) {
                // 3. Build Docker image
                sh "docker build -t ${IMAGE_REGISTRY}/${svc}:${env.IMAGE_TAG} ."

                // 4. Chạy Trivy scan
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
          // 5. Thực thi song song
          parallel buildTasks
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
        script {
          def targetBranch = (env.BRANCH == 'deploy') ? 'product' : env.BRANCH
          withCredentials([usernamePassword(
              credentialsId: 'github-token',
              usernameVariable: 'GIT_USER',
              passwordVariable: 'GIT_PASS'
          )]) {
            if (fileExists('gitops')) {
              sh 'rm -rf gitops'
            }
            sh "git clone https://${GIT_USER}:${GIT_PASS}@github.com/v4224/dacn-gitops.git gitops"

            dir('gitops') {
              def exists = sh(returnStdout: true,
                              script: "git ls-remote --heads origin ${targetBranch} || true").trim()
              if (!exists) {
                sh "git checkout -b ${targetBranch}"
              } else {
                sh "git checkout ${targetBranch}"
              }

              def pathPrefix = (env.BRANCH == 'deploy') ? 'prod' : 'dev'
              def services = env.CHANGED_SERVICES.split(',')
              services.each { svc ->
                def file = "${pathPrefix}/${svc}/${svc}-deployment.yaml"
                sh """
                  sed -i 's#image: .*/${svc}:.*#image: ${IMAGE_REGISTRY}/${svc}:${env.IMAGE_TAG}#' ${file}
                """
              }
              sh 'git config user.name "jenkins-ci"'
              sh 'git config user.email "[email protected]"'
              sh 'git add .'
              sh "git commit -m 'Update image tags to ${env.IMAGE_TAG} [ci skip]' || echo 'No changes to commit'"
              sh "git push https://${GIT_USER}:${GIT_PASS}@github.com/v4224/dacn-gitops.git ${targetBranch}:${targetBranch}"
            }
          }
        }
      }
    }
  }

  post {
    success {
      script {
        if (env.BRANCH == 'deploy') {
          slackSend(channel: '#release', message: "✅ Version ${env.IMAGE_TAG} has been successfully deployed to production.")
        }
      }
    }
    failure {
      script {
        if (env.BRANCH == 'deploy') {
          slackSend(channel: '#release', message: "❌ Failed to deploy version ${env.IMAGE_TAG} to production.")
        }
      }
    }
  }
}
