require "test_helper"

class ProfileControllerTest < ActionDispatch::IntegrationTest
  test "profile page loads" do
    get profile_path
    assert_response :success
    assert_select "h1", "Profile"
  end

  test "saving a resume runs Profilizer and redirects to profile" do
    extraction = ProfileExtraction.new(
      characteristics: Characteristics.new(skills: [ "ruby" ], seniority: "senior"),
      target_roles: [ "Senior Backend Engineer" ]
    )
    fake_llm = Object.new.tap { |o| o.define_singleton_method(:extract) { |**| extraction } }

    LlmClient.stub :new, fake_llm do
      post save_resume_path, params: { resume_text: "Senior backend engineer, 8 years Ruby." }
    end

    assert_redirected_to profile_path
    follow_redirect!
    assert_includes response.body, "Senior Backend Engineer"
  end

  test "uploading a file that isn't actually a PDF redirects with an error instead of crashing" do
    file = fixture_file_upload("not_a_pdf.pdf", "application/pdf")

    post save_resume_path, params: { resume_file: file }

    assert_redirected_to profile_path
    follow_redirect!
    assert_includes response.body, "read as a PDF"
    assert_nil Profile.current.resume_text.presence
  end
end
