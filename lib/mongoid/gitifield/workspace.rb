require 'git'

module Mongoid
  module Gitifield
    class Workspace
      attr_reader :name, :path, :git

      TMP_PATCH_PATH = "/patch".freeze

      def initialize(data: '', folder_name: nil)
        @name = folder_name.presence || "gitifield-#{ DateTime.now.to_s(:nsec) }-#{ rand(10 ** 10).to_s.rjust(10,'0') }"
        @path = Pathname.new(Dir.tmpdir).join(@name)
        @bundle = Bundle.new(data, workspace: self)
      end

      def update(content, date: nil, user: nil)
        init_git_repo if @git.nil?
        File.open(@path.join('content'), 'w') do |file|
          file.write content
          file.fdatasync
        end
        @git.tap(&:add).commit_all('update')
        Commander.exec("git commit --amend --no-edit --date=\"#{ date.strftime('%a %b %e %T %Y +0000') }\"", path: @path) if date.present?
        Commander.exec("git commit --amend --no-edit --author=\"#{ user.name } <#{ user.email }>\"", path: @path) if date.present?
      rescue Git::GitExecuteError
        nil
      end

      def init_git_repo(initial_commit: true)
        FileUtils::mkdir_p(@path)
        FileUtils.touch(@path.join('content'))

        new_repo = File.exists?(@path.join('.git')) != true
        @git = ::Git.init(@path.to_s, log: nil)
        @git.config('user.name', 'Philip Yu')
        @git.config('user.email', 'ht.yu@me.com')

        begin
          @git.tap(&:add).commit_all('initial commit') if new_repo && initial_commit
        rescue Git::GitExecuteError
          # Nothing to do (yet?)
        end
        @git.reset
        @path
      end

      def checkout(id)
        init_git_repo if @git.nil?
        @git.checkout(id)
        content
      end

      def revert(id)
        init_git_repo if @git.nil?
        @git.reset
        @git.checkout_file(id, 'content')
        begin
          @git.tap(&:add).commit_all("Revert to commit #{ id }")
        rescue Git::GitExecuteError
          # Nothing to do (yet?)
        end
      end

      def logs
        init_git_repo if @git.nil?
        @git.log.map {|l| { id: l.sha, date: l.date } }
      end

      def id
        logs.first.try(:[], :id)
      end

      def content
        init_git_repo if @git.nil?
        File.open(@path.join('content'), 'r') do |file|
          file.read
        end
      end

      # file_path be like /data/www/html/sa6.shoplinestg.com/current/aa.patch
      # lc_file_name be like abcd.liquid
      def apply_patch(lc_file_name, patch_path)
        raise ApplyPatchError.new("Please make sure file exist!") unless File.exist?(patch_path)

        before_apply(lc_file_name, patch_path)
        @git.apply(@tmp_patch_path.to_s)
        after_apply
        
        true
      rescue Git::GitExecuteError
        false
      end

      def before_apply(lc_file_name, patch_path)
        patch_name = File.basename(patch_path)
        @tmp_patch_path = @path.join("#{TMP_PATCH_PATH}/#{patch_name}")
        %x(cp #{patch_path} #{@path.join(TMP_PATCH_PATH)})

        @lc_file_path = @path.join(lc_file_name)
        FileUtils.touch(@lc_file_path)
      end

      def after_apply
        File.open(@lc_file_path) do |file|
          update(file.read)
        end

        FileUtils.rm_rf(@lc_file_path)
        FileUtils.rm_rf(@tmp_patch_path)
      end

      def to_s
        init_git_repo if @git.nil?
        @git.reset
        @bundle.pack_up!
      end

      def clean
        @git = nil
        FileUtils.rm_rf(@path)
      end

      class ApplyPatchError < StandardError
      end
    end
  end
end
