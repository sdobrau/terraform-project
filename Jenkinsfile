pipeline {
    parameters {
        string(name: 'TERRAFORM_VERSION',
               defaultValue: '1.15.0-rc2',
               description: "Terraform version to download")
    }
    environment {
        TERRAFORM_VERSION = "${params.TERRAFORM_VERSION}" // pass this as env
        TF_AWS_EXPERIMENT_dynamodb_global_secondary_index = "1"
        GH_TOKEN = credentials('gh_token')
        AWS_ACCESS_KEY_ID = "${params.AWS_ACCESS_KEY_ID}"
        AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')
        AWS_DEFAULT_REGION = "us-east-1"
    }
    agent {
        node {
            label 'worker-nodes'
        }
        dockerfile {
            filename 'Dockerfile'
            dir 'build'
            label 'worker-docker'
            additionalBuildArgs '--build-arg PRODUCT=terraform --build-arg VERSION=${TERRAFORM_VERSION} --build-arg GH_TOKEN=${GH_TOKEN}'
        }
    }
    options {
        timeout(time:5, unit: 'MINUTES')
    }
    stages {
        stage('Notify') {
            steps {
                // Notify a start of build; appends the extra message at the end (note: prefix with separators if needed)
                ircNotify notifyOnStart:true, extraMessage: "Running build ${env.JOB_NAME}... at ${env.BUILD_URL}"
            }
        }
        stage('BetterLeaks') {
            steps {
                sh 'betterleaks git -v .'
            }
        }
        stage('ClamAV') {
            steps {
                sh 'clamscan --recursive .'
            }
        }
        stage ('TerraformValidate') {
            steps {
                sh 'terraform validate'
            }
        }
        stage('TerraformPlan') {
            steps {
                sh 'terraform plan'
            }
        }
        stage('TfLint') {
            steps {
                sh 'tflint --init' // expect .tflint.tcl
                // across builds
                sh 'tflint --recursive'
            }
        }
        stage('Checkov') {
            steps {
                sh 'checkov --quiet --skip-resources-without-violations -d .'
            }
        }
        stage('TrivyConfig') {
            steps {
                sh 'trivy config --report summary .'
            }
        }
        stage('OPA') {
            steps {
                // TODO
                sh 'echo "doing opa"'
            }
        }
        stage('Terratest') {
            steps {
                sh "go mod init ${env.GIT_URL}"
                sh 'go mod tidy'
                sh 'cd test'
                sh 'go test -v -timeout 10m'
            }
            stage('Deploy') {
                when {
                    expression {
                        currentBuild.result == null || currentBuild.result == 'SUCCESS'
                    }
                }
                steps {
                    sh 'terraform apply'
                }
            }
        }
        post {
            always {
                ircNotify targets: "sdobrau #jenkins-room", customMessage:
                "${env.JOB_NAME} run"
            }
            success {
                ircNotify targets: "sdobrau #jenkins-room", customMessage:
                "${env.JOB_NAME} successfully built"
            }
            failure {
                ircNotify targets: "sdobrau #jenkins-room", customMessage:
                "${env.JOB_NAME} successfully built"
                ircNotify targets: "sdobrau #jenkins-room", customMessage:
                "${env.JOB_NAME} failed to build"
            }
        }
}
}
