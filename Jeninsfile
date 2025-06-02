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
    // -------------------------------------
    // 1. CHECKPOINT: Chỉ cho phép chạy tiếp
    //    nếu là commit trên develop hoặc tag (giả định tag tạo từ deploy)
    // -------------------------------------
    stage('Validate Run Context') {
      when {
        anyOf {
          branch 'develop'
          buildingTag()
        }
      }
      steps {
        echo "✅ Điều kiện chạy hợp lệ: branch/develop hoặc đang build tag"
      }
    }

    // -------------------------------------
    // 2. CHECKOUT SOURCE
    //    - Nếu buildingTag(), Jenkins sẽ set env.TAG_NAME = <tag>
    //      và giả định tag được tạo từ branch deploy
    //    - Nếu build trên develop, branch bình thường
    // -------------------------------------
    stage('Checkout Source') {
      when {
        anyOf {
          branch 'develop'
          buildingTag()
        }
      }
      steps {
        // Dùng Multibranch Pipeline để checkout đúng nhánh hoặc tag
        checkout scm

        script {
          def rawBranch = env.GIT_BRANCH
          echo "GIT_BRANCH = ${rawBranch}"

          if (rawBranch?.startsWith("refs/tags/")) {
            // Đang build tag
            env.TAG_NAME = rawBranch.replace("refs/tags/", "")
            // Giả định tag chỉ được tạo từ nhánh deploy
            env.BRANCH = "deploy"
            echo "→ Detected a tag build: ${env.TAG_NAME} (tự động gán BRANCH=deploy)"
          } else {
            // Đang build một nhánh (thường là develop)
            env.TAG_NAME = ""
            env.BRANCH = env.BRANCH_NAME
            echo "→ Detected a branch build: ${env.BRANCH}"
          }
        }
      }
    }

    // -------------------------------------
    // 3. SET IMAGE TAG
    //    - Nếu BRANCH=deploy (tag hoặc commit deploy), gắn prefix prod-
    //    - Ngược lại (develop hoặc feature), gắn <branch>-<shortSHA>
    // -------------------------------------
    stage('Set Image Tag') {
      when {
        anyOf {
          branch 'develop'
          buildingTag()
        }
      }
      steps {
        script {
          def branch = env.BRANCH ?: "develop"
          if (branch == 'deploy') {
            // Tag build hoặc commit thẳng trên deploy (thường chỉ tag)
            env.IMAGE_TAG = "prod-${env.TAG_NAME ?: env.BUILD_ID}"
            env.RUN_SONAR  = "false"
          } else {
            // Branch develop hoặc các feature khác
            def commitHash = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
            env.IMAGE_TAG = "${branch}-${commitHash}"
            env.RUN_SONAR  = "true"
          }

          echo "Image tag = ${env.IMAGE_TAG}"
          echo "Run SonarQube? => ${env.RUN_SONAR}"
        }
      }
    }

    // -------------------------------------
    // 4. DETECT CHANGED SERVICES
    //    - Nếu trình build là deploy (tag), build Toàn bộ
    //    - Nếu là develop, so sánh với origin/develop
    // -------------------------------------
    stage('Detect Changed Services') {
      when {
        anyOf {
          branch 'develop'
          buildingTag()
        }
      }
      steps {
        script {
          def all = ALL_SERVICES.split(',')
          if (env.BRANCH == 'deploy') {
            // Tag build → build tất cả
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
                echo "No changes in service folders → build all"
                env.CHANGED_SERVICES = all.join(',')
              }
            } else {
              echo "No files changed compared to origin/${env.BRANCH} → build all"
              env.CHANGED_SERVICES = all.join(',')
            }
          }
          echo "Services to build: ${env.CHANGED_SERVICES}"
        }
      }
    }

    // -------------------------------------
    // 5. SONARQUBE ANALYSIS
    //    - Chỉ chạy khi RUN_SONAR=true (tức nhánh develop, không phải tag)
    //    - Chỉ scan những service trong CHANGED_SERVICES
    // -------------------------------------
    stage('SonarQube Analysis') {
      when {
        allOf {
          expression { return env.RUN_SONAR == 'true' }
          expression { return env.CHANGED_SERVICES?.trim() }
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
            // Bắt buộc Quality Gate pass, nếu fail → pipeline dừng
            timeout(time: 15, unit: 'MINUTES') {
              waitForQualityGate(abortPipeline: true)
            }
          }
        }
        failure {
          echo "⚠️ SonarQube Analysis gặp lỗi."
        }
      }
    }

    // -------------------------------------
    // 6. BUILD & SCAN DOCKER IMAGES
    //    - Chạy trên develop (commit) và chạy trên deploy (tag) đều được
    // -------------------------------------
    stage('Build & Scan Docker Images') {
      when {
        anyOf {
          branch 'develop'
          buildingTag()
        }
      }
      steps {
        script {
          // Login Docker Hub
          sh "echo ${REGISTRY_CRED_PSW} | docker login -u ${REGISTRY_CRED_USR} --password-stdin"

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
                echo "→ Trivy scan for ${svc} done"
              }
            }
          }
          parallel buildTasks
        }
      }
    }

    // -------------------------------------
    // 7. PUSH IMAGES
    // -------------------------------------
    stage('Push Images') {
      when {
        anyOf {
          branch 'develop'
          buildingTag()
        }
      }
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

    // -------------------------------------
    // 8. UPDATE GITOPS MANIFESTS
    // -------------------------------------
    stage('Update GitOps Manifests') {
      when {
        anyOf {
          branch 'develop'
          buildingTag()
        }
      }
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

    // -------------------------------------
    // 9. GENERATE CHANGELOG (chỉ khi tag từ deploy)
    // -------------------------------------
    stage('Generate Changelog (for prod)') {
      when {
        expression {
          // Chỉ chạy khi thực sự có tag, và giả định tag từ deploy
          return (env.TAG_NAME?.trim() && env.BRANCH == 'deploy')
        }
      }
      steps {
        script {
          echo "→ Generating changelog for tag: ${env.TAG_NAME}"

          def prevTag = sh(returnStdout: true,
                          script: "git describe --tags --abbrev=0 \$(git rev-list --tags --skip=1 --max-count=1)").trim()
          echo "Previous tag: ${prevTag}"

          def changelog = sh(returnStdout: true,
                            script: "git log ${prevTag}..${env.TAG_NAME} --pretty=format:'- %s'").trim()
          def changelogFile = "gitops/changelogs/release-${env.TAG_NAME}.md"
          writeFile file: changelogFile, text: changelog

          dir('gitops') {
            sh 'git add changelogs/'
            sh "git commit -m 'Add changelog for ${env.TAG_NAME}' || echo 'No changes to commit'"
            sh "git push origin ${env.BRANCH}"
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
