module VCAP::CloudController
  class BuildpackBitsController < RestController::ModelController
    def self.dependencies
      [:buildpack_blobstore, :upload_handler]
    end

    path_base 'buildpacks'
    model_class_name :Buildpack
    allow_unauthenticated_access only: :download
    authenticate_basic_auth("#{path}/*/download") do
      [VCAP::CloudController::Config.config[:staging][:auth][:user],
       VCAP::CloudController::Config.config[:staging][:auth][:password]]
    end

    put "#{path_guid}/bits", :upload
    def upload(guid)
      buildpack = find_guid_and_validate_access(:upload, guid)
      raise Errors::ApiError.new_from_details('BuildpackLocked') if buildpack.locked?

      uploaded_file = upload_handler.uploaded_file(params, 'buildpack')#要 upload的file
      uploaded_filename = upload_handler.uploaded_filename(params, 'buildpack')#要 upload 的filename

      logger.info "Uploading bits for #{buildpack.name}, file: uploaded_filename"

      raise Errors::ApiError.new_from_details('BuildpackBitsUploadInvalid', 'a filename must be specified') if uploaded_filename.to_s == ''
      raise Errors::ApiError.new_from_details('BuildpackBitsUploadInvalid', 'only zip files allowed') unless File.extname(uploaded_filename) == '.zip'
      raise Errors::ApiError.new_from_details('BuildpackBitsUploadInvalid', 'a file must be provided') if uploaded_file.to_s == ''

      uploaded_filename = File.basename(uploaded_filename)

      upload_buildpack = UploadBuildpack.new(buildpack_blobstore)
      #1.	如果buildpack的key不为空，但是buildpack在blobstore中不存在，则将buildpack复制到blobstore中
      #          a)	cp_to_blobstore(source_path, destination_key, retries=2)
      #             1.	根据source_path打开源文件，
      #             2.	每个文件进行files create，创建的文件的key为destination_key
      #2.	更新buildpack 的key为new_key ，filename为newfilenama
      #3.	如果blobstore中依旧存在旧的buildpack则删除

      if upload_buildpack.upload_buildpack(buildpack, uploaded_file, uploaded_filename)
        [HTTP::CREATED, object_renderer.render_json(self.class, buildpack, @opts)]
      else
        [HTTP::NO_CONTENT, nil]
      end
    ensure
      FileUtils.rm_f(uploaded_file) if uploaded_file
    end

    get "#{path_guid}/download", :download

    #1.	如果存在于本地则调用
    #     def send_file(path, opts={})#最终调用sinatra的send_file
    #2.	如果不存在与本地，则重定向到download url

      def download(guid)
      obj = Buildpack.find(guid: guid)

      blob = buildpack_blobstore.blob(obj.key) if obj && obj.key
      raise Errors::ApiError.new_from_details('NotFound', guid) unless blob

      if @buildpack_blobstore.local?
        send_local_blob(blob)
      else
        return [HTTP::FOUND, { 'Location' => blob.download_url }, nil]
      end
    end

    private

    attr_reader :buildpack_blobstore, :upload_handler

    def inject_dependencies(dependencies)
      super
      @buildpack_blobstore = dependencies[:buildpack_blobstore]
      @upload_handler = dependencies[:upload_handler]
    end

    def send_local_blob(blob)
      if @config[:nginx][:use_nginx]
        url = blob.download_url
        logger.debug "nginx redirect #{url}"
        return [200, { 'X-Accel-Redirect' => url }, '']
      else
        return send_file blob.local_path
      end
    end
  end
end
