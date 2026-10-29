require 'open3'
require 'yaml'
require 'json'
require 'ostruct'
require 'fileutils'
require 'rbconfig'

def os
  host_os = RbConfig::CONFIG['host_os']
  case host_os
  when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
    :windows
  when /darwin|mac os/
    :macosx
  when /linux/
    :linux
  when /solaris|bsd/
    :unix
  else
    raise "Unknown Operating System: #{host_os.inspect}"
  end
end

class Projects

  def initialize
    @metadata = YAML.load_file 'projects.yaml'
  end

  def self.load
    new
  end

  def projects
    @metadata['projects']
  end

  def images
    projects.select { |k,v| v['type'] == 'image' }
  end

  def list
    puts 'Listing all projects ...'
    puts projects.to_yaml
  end

end

class DockerImage

  attr_reader :name, :version, :registry, :aws_account, :aws_region, :tags

  def initialize(metadata)
    @name, data = metadata.to_a
    @data       = OpenStruct.new data.merge({ name: name })
    @version    = @data.version || ENV['GO_PIPELINE_LABEL']
    @tags       = [@version, @data.tags, ENV['GO_PIPELINE_LABEL']].flatten.compact.uniq
  end

  def aws_account
    @aws_account ||= aws_sts_get_caller_identity
  end

  def aws_region
    @aws_region ||= get_aws_region
  end

  def build_and_tag_and_push_and_push_tags
    check_duplicate_image
    build; tag; push; push_tags
  ensure
    cleanup
  end
  alias_method :publish, :build_and_tag_and_push_and_push_tags

  def build
    do_ecr_login unless has_login?
    render_build_file
    puts "Building Image: #{name}:#{version}"
    cmd = %{ docker build -f #{build_file} --build-arg version=#{version} --build-arg BUILD_VERSION=#{version} -t #{name}:#{version} . }
    raise 'ERROR: Build Failed' unless execute cmd
  ensure
    puts 'Removing temporary Dockerfile ...'
    FileUtils.rm build_file if ::File.exist? build_file
    scrub_dangling_images
  end

  def tag(extra_tags=[])
    (tags | extra_tags).each do |tag|
      puts "Tagging Image: #{name}:#{tag}"
      tag_local "#{name}:#{tag}"
    end
  end

  def push
    do_ecr_login unless has_login?
    ecr_repo_create unless has_ecr_repo?
    if has_ecr_repo?
      check_duplicate_image
      tag = tag_local(ecr_image_signature)
      puts "Pushing Image: #{tag}"
      cmd = %{ docker push #{tag} }
      raise 'ERROR: Push Failed' unless execute cmd
    end
  end

  def push_tags(extra_tags=[])
    do_ecr_login unless has_login?
    if has_ecr_repo?
      (tags | extra_tags).each do |tag|
        puts "Pushing Tag: #{registry}/#{name}:#{tag}"
        aws_ecr_put_image name, tag, manifest
      end
    end
  end

  def copy_images(tag)
    sit1_image_link = "136622757876.dkr.ecr.us-west-2.amazonaws.com/#{name}:#{version}"

    pull_image = "docker pull #{sit1_image_link}"
    raise 'ERROR: Pulling image from ECS failed' unless execute pull_image

    [tag, version].each do |image_version|
      destination_image_link = "#{registry}/#{name}:#{image_version}"
      puts "Tagging Image: #{image_version}"
      tag_image_cmd = "docker tag #{sit1_image_link} #{destination_image_link}"
      raise 'ERROR: Tagging image failed' unless execute tag_image_cmd

      puts "Pushing Image: #{image_version}"
      push_image_cmd = "docker push #{destination_image_link}"
      raise 'ERROR: Pushing image failed' unless execute push_image_cmd
    end

    puts "Removing Images..."
    remove_image_cmd = "docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep '#{name}')"
    raise 'ERROR: Removing images failed' unless execute remove_image_cmd
  end

  def manifest
    cmd = %W{
      aws ecr batch-get-image
      --repository-name #{name}
      --image-ids imageTag=#{version}
      --query "images[].imageManifest"
      --output text
    }.join(' ')
    @manifest ||= exec_aws cmd
  end

  private

  def get_aws_region
    ENV['AWS_REGION'] || ENV['AWS_DEFAULT_REGION'] || aws_configure_get_region
  end

  def aws_configure_get_region
    exec_aws 'aws configure get region'
  end

  def aws_sts_get_caller_identity
    exec_aws 'aws sts get-caller-identity --query Account --output text'
  end

  def tag_local(tag)
    cmd = %{ docker tag #{name}:#{version} #{tag} }
    raise 'ERROR: Tagging Failed' unless execute cmd
    tag
  end

  def aws_ecr_put_image(name, tag, manifest)
    return true if registry_tags.include? tag
    cmd = %W{
      aws ecr put-image
      --repository-name #{name}
      --image-tag #{tag}
      --image-manifest '#{manifest}'
    }.join(' ')
    raise 'ERROR: Tagging Failed' unless execute cmd
  end

  def dockerfile_data
    ::File.read @data.dockerfile
  end

  def label
    kv = @data.to_h.inject([]) { |memo,(k,v)| memo << %{#{k}="#{v}"} }
    %{\n\nLABEL  #{kv.join(' ')}\n\n}
  end

  def build_file
    'Dockerfile.build'
  end

  def render_build_file
    ::File.write build_file, (dockerfile_data + label)
  end

  def registry_tags
    cmd = %W{
      aws ecr describe-images
      --repository-name #{name}
      --image-ids imageTag=#{version}
      --query "imageDetails[].imageTags[]"
      --output json
    }.join(' ')
    @registry_tags ||= JSON.parse(exec_aws cmd)
  rescue
    []
  end

  def registry_list_images
    JSON.parse(%x{ aws ecr list-images --repository-name #{name} })['imageIds']
  rescue
    []
  end

  def ecr_image_signature
    "#{registry}/#{name}:#{version}"
  end

  def registry_has_image?
    @seatbelt ||= registry_list_images.find { |e| e['imageTag'] == version }
  end

  def scrub_dangling_images
    puts "Scrubbing dangling images ..."
    puts %x{ docker rmi -f `docker images -f dangling=true -q` 2> /dev/null }
  rescue
  end

  def scrub_image_artifacts
    puts "Scrubbing images we built ..."
    puts %x{ docker rmi -f `docker images #{name} -q` 2> /dev/null }
  rescue
  end

  def cleanup
    puts "Cleaning up ..."
    scrub_dangling_images; scrub_image_artifacts
  rescue
  end
  alias_method :clean, :cleanup

  def check_duplicate_image
    raise "ERROR: #{ecr_image_signature} already exists!" if registry_has_image?
  end

  def registry
    @registry ||= "#{aws_account}.dkr.ecr.#{aws_region}.amazonaws.com"
  end

  def has_login?
    @has_login ||= false
  end

  def ecr_password
    exec_aws "aws ecr get-login-password --region #{aws_region} --output text"
  end

  def do_ecr_login
    puts "Logging into ECR ..."
    cmd = %W{
      docker login
      --username AWS
      --password #{ecr_password}
      #{registry}
    }.join(' ')
    cmd = if os == :windows
            %x{#{cmd}}.chomp
          else
            "#{cmd} 2> /dev/null"
          end
    raise 'ERROR: Login Failed' unless execute cmd
    @has_login = true
  end

  def has_ecr_repo?
    begin
      puts "Checking ECR repo exists ... #{name}"
      cmd = %{ aws ecr describe-repositories --repository-names #{name} }
      raise 'ERROR: ECR Check Failed' unless execute cmd
      @repo_check = true
    rescue
      puts "Repository not found"
      @repo_check = false
    end
    @repo_check ||= false
  end

  def ecr_repo_create
    puts "Creating new repository..."
    cmd = %{ aws ecr create-repository --repository-name #{name} }
    raise 'ERROR: Failed to create Repository' unless execute cmd
  end

  def execute(cmd)
    Open3.popen2e(cmd) do |stdin, stdout_err, wait_thru|
      puts $_ while stdout_err.gets
      wait_thru.value.success?
    end
  end

  def exec_aws(cmd)
    result = %x{#{cmd}}.chomp!
    raise 'ERROR: Execution failed or returned no results' unless result
    result
  end

end

##############################################################
# MAIN
##############################################################

projects = Projects.load

task default: %w{ list_projects }

desc 'List known projects'
task :list_projects do
  projects.list
end

desc "push images from sit1 to other accounts"
task 'copy_images_from_sit1', [:tag] do  |t,args|
  raise 'ERROR: No tag was specified' unless image_tag = args[:tag]
  projects.images.each { |data| DockerImage.new(data).copy_images(image_tag) }
    puts 'Complete'
end

%i{ build tag push push_tags publish clean }.each do |cmd|

  desc "#{cmd.capitalize} a single project, by name"
  task cmd, [:name] do |t,args|
    raise 'ERROR: No project name specified' unless args[:name]
    argArray = args.to_a
    name = argArray.shift
    argArray = argArray.empty? ? [cmd] : [cmd, argArray]
    project = projects.images.find { |k,v| k == name }
    DockerImage.new(project).send *argArray
    puts 'Complete'
  end

  desc "#{cmd.capitalize} all projects"
  task "#{cmd}_all".to_sym do |t,args|
    projects.images.each do |data|
      argArray = args.to_a
      argArray = argArray.empty? ? [cmd] : [cmd, argArray]
      DockerImage.new(data).send *argArray
    end
    puts 'Complete'
  end

end
