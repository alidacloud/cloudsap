# frozen_string_literal: true

# Fix for https://github.com/erikhuda/thor/issues/398
class Thor
  module Shell
    class Basic
      def print_wrapped(message, options = {})
        indent = (options[:indent] || 0).to_i
        if indent.zero?
          stdout.puts message
        else
          message.each_line do |message_line|
            stdout.print ' ' * indent
            stdout.puts message_line.chomp
          end
        end
      end
    end
  end
end

# rubocop:disable Layout/HeredocIndentation
module Cloudsap
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    # rubocop:disable Metrics/BlockLength
    no_commands do
      def setup_rack(registry)
        Rack::Builder.new do
          use Rack::Deflater
          use Prometheus::Middleware::Exporter, registry: registry
          map '/health' do
            run ->(_env) { [200, { 'Content-Type' => 'text/html' }, ['OK']] }
          end
        end
      end

      def future_proofer(futures)
        timer = Concurrent::TimerTask.new do
          futures.each_with_index do |future, index|
            if future.rejected?
              Cloudsap::Common.logger.error("#{future.class}: #{future.reason}")
            end
            futures.delete_at(index) if future.complete?
          end
        end
        timer.execution_interval = 1
        timer.timeout_interval   = 5
        timer
      end

      def start_watch(api_group, api_version, metrics)
        Thread.report_on_exception = true
        Thread.abort_on_exception = true
        watcher = Cloudsap::Watcher.new(api_group, api_version, metrics)
        future_proofer(watcher.futures).execute
        Thread.new do
          watcher.watch
        rescue StandardError => e
          Cloudsap::Common.log_exception(e)
          Cloudsap::Common.show_backtrace(e)
          sleep 5
          metrics.restart
          retry
        end
      end
    end
    # rubocop:enable Metrics/BlockLength

    desc 'controller', 'Run Cloudsap controller'
    long_desc <<~LONGDESC

    The `cloudsap contoller` subcommand launches the Cloudsap operator and
    begins monitoring your cluster for any changes to CloudServiceAccount
    resources.

    -----------------------------------------------
     CLI OPTION      ||  DESCRIPTION
    -----------------------------------------------
    --aws-region    ||  AWS region that hosts your EKS cluster (required)
    --cluster-name  ||  Name designated for the EKS cluster (required)
    --oidc-issuer   ||  URL of the EKS cluster's OIDC issuer
    --kubeconfig    ||  Path to kubeconfig file for authentication
    --debug         ||  Enable debug logging
    --iam-retry     ||  Maximum retries for iam client (Default: 3)
    -----------------------------------------------

    It can be configured via commandline options above or its equivalent shell
    environment variable.

    -----------------------------------------------
     CLI OPTION     ||  ENVIRONMENT VARIABLE
    -----------------------------------------------
    --aws-region    ||  AWS_REGION
    --cluster-name  ||  CLOUDSAP_CLUSTER_NAME
    --oidc-issuer   ||  CLOUDSAP_OIDC_ISSUER
    --kubeconfig    ||  KUBECONFIG
    --debug         ||  CLOUDSAP_DEBUG
    --iam-retry     ||  IAM_RETRY
    -----------------------------------------------

    For more information, visit the project homepage ...

    https://github.com/dayglojesus/cloudsap

    LONGDESC
    option :aws_region,   type: :string,  default: ENV['AWS_REGION'], required: true
    option :cluster_name, type: :string,  default: ENV['CLOUDSAP_CLUSTER_NAME'], required: true
    option :oidc_issuer,  type: :string,  default: ENV['CLOUDSAP_OIDC_ISSUER'], required: false
    option :kubeconfig,   type: :string,  default: ENV['KUBECONFIG'], required: false
    option :debug,        type: :boolean, default: (ENV['CLOUDSAP_DEBUG'] || false)
    option :iam_retry,    type: :string, default: (ENV['IAM_RETRY'] || '3')

    def controller
      $stdout.sync = true

      ENV['RACK_ENV'] = 'production'

      Cloudsap::Common.setup(options)

      registry = Prometheus::Client.registry
      metrics  = Cloudsap::Metrics.new(registry)

      start_watch(API_GROUP, API_VERSION, metrics)

      Thin::Logging.logger = Cloudsap::Common.logger
      Rack::Server.start(app: setup_rack(registry))
    end

    desc 'install COMPONENT', 'Install Cloudsap IRSA or generate install manifests'
    long_desc <<~LONGDESC

    The `cloudsap install COMPONENT` subcommand perfoms installations of
    Cloudsap and its prerequisties:

    1. `cloudsap install irsa`

       Installs an AWS IAM Role for ServiceAccounts for Cloudsap itself.
       Cloudsap requires an IRSA to begin managing the IAM resources associated
       with any newly created `CloudServiceAccount`.

    2. `cloudsap install full`

       Emits a manifest you can use to install the Cloudsap operator to your
       cluster. Once emitted, the manifest can be reviewed and edited before
       applying it to your cluster.

    2. `cloudsap install crd`

       Emits a manifest containing the CRD for the CloudServiceAccounts.

    -----------------------------------------------
     CLI OPTION     ||  DESCRIPTION
    -----------------------------------------------
    --aws-region    ||  AWS region that hosts your EKS cluster (required)
    --cluster-name  ||  Name designated for the EKS cluster (required)
    --namespace     ||  Namespace in which to deploy operator (required)
    --kubeconfig    ||  Path to kubeconfig file for authentication
    --iam-retry     ||  Maximum retries for iam client (Default: 3)
    -----------------------------------------------

    It can be configured via commandline options above or its equivalent shell
    environment variable.

    -----------------------------------------------
     CLI OPTION     ||  ENVIRONMENT VARIABLE
    -----------------------------------------------
    --aws-region    ||  AWS_REGION
    --cluster-name  ||  CLOUDSAP_CLUSTER_NAME
    --namespace     ||  CLOUDSAP_NAMESPACE
    --kubeconfig    ||  KUBECONFIG
    --iam-retry     ||  IAM_RETRY
    -----------------------------------------------

    For more information, visit the project homepage ...

    https://github.com/dayglojesus/cloudsap

    LONGDESC
    option :aws_region,   type: :string, default: ENV['AWS_REGION'], required: true
    option :cluster_name, type: :string, default: ENV['CLOUDSAP_CLUSTER_NAME'], required: true
    option :namespace,    type: :string, default: ENV['CLOUDSAP_NAMESPACE'], required: true
    option :kubeconfig,   type: :string, default: ENV['KUBECONFIG'], required: false
    option :iam_retry,    type: :string, default: (ENV['IAM_RETRY'] || '3')
    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    def install(component)
      $stdout.sync = true
      Cloudsap::Common.options = options
      Cloudsap::Common.set_plaintext_logger
      case component.to_sym
      when :irsa
        Cloudsap::Common.setup(options)
        Cloudsap::Aws::IamRole.irsa(PROGRAM_NAME, options.namespace).apply
      when :crd
        IO.foreach("#{Cloudsap::Common.assets}/cloudserviceaccount.yaml") { |line| puts line }
      when :full
        values = {
          aws_region: options.aws_region,
          cluster_name: options.cluster_name,
          namespace: options.namespace,
          account_id: Cloudsap::Common.account_id
        }
        manifest = "#{Cloudsap::Common.assets}/full_install_manifest.erb"
        puts ERB.new(File.read(manifest)).result_with_hash(values)
      else
        msg = %(Invalid argument -- I don't know how to install: #{component})
        Cloudsap::Common.logger.fatal(msg)
        exit 1
      end
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength
  end
end
# rubocop:enable Layout/HeredocIndentation
