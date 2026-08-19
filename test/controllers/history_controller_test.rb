require "test_helper"

class HistoryControllerTest < ActionDispatch::IntegrationTest
  test "history page loads with no jobs" do
    get history_path
    assert_response :success
    assert_includes response.body, "No job opportunities recorded yet."
  end
end
