class ProfileController < ApplicationController
  def show
    @profile = Profile.current
  end

  def save_resume
    text = extract_resume_text
    return if text.nil? # extract_resume_text already redirected with an error

    extraction = Profilizer.call(resume_text: text, llm: LlmClient.new)
    Profile.current.update!(
      resume_text: text,
      characteristics: extraction.characteristics.attributes,
      target_roles: extraction.target_roles
    )
    redirect_to profile_path
  end

  def save_target_roles
    roles = params[:target_roles].to_s.split(",").map(&:strip).reject(&:blank?)
    Profile.current.update!(target_roles: roles)
    redirect_to profile_path
  end

  def save_preferences
    cities = params[:preferred_cities].to_s.split(",").map(&:strip).reject(&:blank?)
    modes = Array(params[:preferred_modes]).reject(&:blank?)
    Profile.current.update!(
      min_salary: params[:min_salary].presence,
      preferred_cities: cities,
      preferred_modes: modes
    )
    redirect_to profile_path
  end

  private

  # Returns the extracted text, or nil after redirecting with an error if
  # the uploaded file isn't actually a readable PDF (accept="application/
  # pdf" on the file input is client-side only — a corrupted, encrypted,
  # or misnamed file still reaches here).
  def extract_resume_text
    return params[:resume_text].to_s if params[:resume_file].blank?

    PDF::Reader.new(params[:resume_file].tempfile.path).pages.map(&:text).join("\n")
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
    redirect_to profile_path, alert: "That file couldn't be read as a PDF. Try a different file, or paste the text instead."
    nil
  end
end
