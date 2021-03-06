class CandidatesController < AuthenticatedController
  load_and_authorize_resource :except => [:create, :update ]

  MAX_FILE_SIZE = 10 * 1024 * 1024

  include ApplicationHelper

  def index
    # TODO: too many cases, we need a neat approach here.
    if params.has_key? :no_openings
      @candidates = Candidate.active.without_opening.order(sort_column('Candidate') + ' ' + sort_direction).paginate(:page => params[:page])
    elsif params.has_key? :no_interviews
      @candidates = Candidate.active.without_interview.order(sort_column('Candidate') + ' ' + sort_direction).paginate(:page => params[:page])
    elsif params.has_key? :with_assessment
      @candidates = Candidate.active.with_assessment.order(sort_column('Candidate') + ' ' + sort_direction).paginate(:page => params[:page])
    elsif params.has_key? :without_assessment
      @candidates = Candidate.active.without_assessment.paginate(:page => params[:page])
    elsif params.has_key? :with_opening
      @candidates = Candidate.active.with_opening.order(sort_column('Candidate') + ' ' + sort_direction).paginate(:page => params[:page])
    elsif params.has_key? :inactive
      @candidates = Candidate.inactive.order(sort_column('Candidate') + ' ' + sort_direction).paginate(:page => params[:page])
    elsif params.has_key? :available
      @candidates = Candidate.available.order(sort_column('Candidate') + ' ' + sort_direction).paginate(:page => params[:page])
    elsif params.has_key? :all
      @candidates = Candidate.paginate(:page => params[:page])
    else
      opening = nil
      if (params[:opening_id])
        opening = Opening.find(params[:opening_id])
      end
      if opening
        @candidates = opening.candidates.active.paginate(:page => params[:page])
      else
        # NOTE: show active candidates by default
        @candidates = Candidate.active.order(sort_column('Opening') + ' ' + sort_direction).paginate(:page => params[:page])
      end
    end

    if params.has_key? :partial
      render partial: 'candidates/candidates_index'
    end
  end

  def show
    unless params[:legacy].nil?
      @candidate = Candidate.find params[:id]
      @resume = @candidate.resume.name unless @candidate.resume.nil?
      return render 'legacy_show'
    end
    @candidate = Candidate.find params[:id]
    @latest_applying_job = @candidate.opening_candidates.last
    @opening_candidate = nil
    @opening = nil
    @interviews = []
    @assessment = nil
    unless @latest_applying_job.nil?
      @opening_candidate = @latest_applying_job # to fit the assessment form
      @opening = @latest_applying_job.opening
      @interviews = @latest_applying_job.interviews
      @assessment = Assessment.new(:opening_candidate_id => @latest_applying_job.id,
                                   :creator => current_user)
    end

    @applying_jobs = nil
    unless @latest_applying_job.nil?
      @applying_jobs = @candidate.opening_candidates.where("opening_candidates.id != #{@latest_applying_job.id}")
    end

    @resume = @candidate.resume.name unless @candidate.resume.nil?
  end

  def new
    @candidate = Candidate.new
  end

  def edit
    @candidate = Candidate.find params[:id]
    @resume = @candidate.resume.name unless @candidate.resume.nil?
  end

  def new_opening
    @candidate = Candidate.find params[:id]
    assigned_departments = get_assigned_departments(@candidate)
    @selected_department_id = assigned_departments[0].try(:id)
    render :action => :new_opening, :layout => false
  end


  # GET /edit_candidates
  def index_for_selection
    if params[:exclude_opening_id]
      exclude_opening = Opening.find(params[:exclude_opening_id])
      @candidates = Candidate.active.not_in_opening(exclude_opening.id).paginate(:page => params[:page])
    else
      @candidates = Candidate.active.paginate(:page => params[:page])
    end
    render :action => :index_for_selection, :layout => false
  rescue ActiveRecord::RecordNotFound
    return render :text => "", notice: 'Invalid opening'
  end



  def create
    tempio = nil
    unless params[:candidate][:resume].nil?
      tempio = params[:candidate][:resume]
      params[:candidate].delete(:resume)
    end

    params[:candidate].delete(:department_id)
    opening_id = params[:candidate][:opening_ids]
    params[:candidate].delete(:opening_ids)
    authorize! :create, Candidate
    @candidate = Candidate.new params[:candidate]
    if @candidate.save
      if opening_id
        @candidate.opening_candidates.create(:opening_id => opening_id)
      end

      #TODO: async large file upload
      unless tempio.nil?
        if tempio.size > MAX_FILE_SIZE
          render :status => 400, :json => {:message => 'File size cannot be larger than 10M.'}
          return
        end

        @resume = @candidate.build_resume
        @resume.savefile(tempio.original_filename, tempio)
      end

      redirect_to @candidate, :notice => "Candidate \"#{@candidate.name}\" (#{@candidate.email}) was successfully created."
    else
      render :action => 'new'
    end
  end


  def create_opening
    @candidate = Candidate.find params[:id]
    unless params[:candidate]
      redirect_to @candidate, notice: 'Invalid attributes'
      return
    end
    new_opening_id = params[:candidate][:opening_ids].to_i
    if new_opening_id == 0
      redirect_to @candidate, :notice => "Opening was not given."
      return
    end
    if @candidate.opening_ids.index(new_opening_id)
      redirect_to @candidate, :notice => "Opening was already assigned."
      return
    end
    if @candidate.opening_candidates.create(:opening_id => new_opening_id)
      redirect_to @candidate, :notice => "Opening was successfully assigned."
    else
      redirect_to @candidate, :notice => "Opening was already assigned or not given."
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to candidates_url, notice: 'Invalid Candidate'
  end

  #Don't support remove JD assignment via update API
  #To avoid removing a JD assignment accidentally, should use 'create_opening' instead.
  def update
    @candidate = Candidate.find params[:id]
    unless params[:candidate]
      redirect_to @candidate, notice: 'Invalid parameters'
      return
    end
    params[:candidate].delete(:department_id)
    params[:candidate].delete(:opening_ids)

    tempio = nil
    unless params[:candidate][:resume].nil?
      tempio = params[:candidate][:resume]
      params[:candidate].delete(:resume)
    end

    authorize! :update, Candidate

    if @candidate.update_attributes(params[:candidate])
      unless tempio.nil?
        if tempio.size > MAX_FILE_SIZE
          render :status => 400, :json => {:message => 'File size cannot be larger than 10M.'}
          return
        end

        #TODO: async large file upload
        if @candidate.resume.nil?
          @resume = @candidate.build_resume
          @resume.savefile(tempio.original_filename, tempio)
        else
          @candidate.resume.updatefile(tempio.original_filename, tempio)
        end
      end
      redirect_to @candidate, :notice => "Candidate \"#{@candidate.name}\" (#{@candidate.email}) was successfully updated."
    else
      @resume = @candidate.resume.name unless @candidate.resume.nil?
      render :action => 'edit'
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to candidates_url, notice: 'Invalid Candidate'
  end

  def move_to_blacklist
    @candidate = Candidate.find(params[:id])
    @candidate.mark_inactive

    redirect_to candidates_url, :notice => "Candidate \"#{@candidate.name}\" (#{@candidate.email}) was successfully moved to blacklist."
  rescue ActiveRecord::RecordNotFound
    redirect_to users_url, notice: 'Invalid user'
  rescue
    redirect_to candidates_url, :error => "Candidate \"#{@candidate.name}\" (#{@candidate.email}) cannot be moved to blacklist."
  end

  # NOTE: keep the destroy method since we are not sure whether it is needed or not
  def destroy
    @candidate = Candidate.find(params[:id])
    @resume = @candidate.resume
    @resume.deletefile unless @resume.nil?
    @candidate.destroy

    redirect_to candidates_url, :notice => "Candidate \"#{@candidate.name}\" (#{@candidate.email}) was successfully deleted."
  rescue ActiveRecord::RecordNotFound
    redirect_to users_url, notice: 'Invalid user'
  rescue
    redirect_to candidates_url, :error => "Candidate \"#{@candidate.name}\" (#{@candidate.email}) cannot be deleted."
  end

  def resume
    @candidate = Candidate.find params[:id]
    @resume = @candidate.resume

    unless @resume.nil?
      path = File.join(download_folder, "#{Time.now.to_s}.#{@resume.name}")
      fp = File.new(path, 'wb')
      @resume.readfile(fp)
      fp.close
      download_file(path)
    end
  end

private
  def get_assigned_departments(candidate)
    opening_candidates = candidate.opening_candidates
    # NOTE: Currently one candidate cannot be assigned to multiple opening jobs on web UI
    assigned_departments = []
    if opening_candidates.size > 0
      opening_id = opening_candidates[0].opening_id
      assigned_departments = Department.joins(:openings).where( "openings.id = ?", opening_id )
    end
    return assigned_departments
  end

  def download_folder
    folder = Rails.root.join('public', 'download')
    Dir.mkdir(folder) unless File.exists?(folder)
    folder
  end

  def download_file(filepath)
    mimetype = MIME::Types.type_for(filepath)
    filename = File.basename(filepath)
    File.open(filepath) do |fp|
      send_data(fp.read, :filename => filename, :type => "#{mimetype[0]}", :disposition => "inline")
    end
    File.delete(filepath)
  end

end
