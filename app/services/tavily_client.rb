# Thin adapter over Tavily's REST API, called directly via Faraday — no
# Tavily gem exists (confirmed during the grilling session). Same reasoning
# as LlmClient: Searcher is tested against this interface with a fake,
# never against the real Tavily API.
class TavilyClient
  SEARCH_ENDPOINT = "https://api.tavily.com/search"
  EXTRACT_ENDPOINT = "https://api.tavily.com/extract"

  def initialize(api_key: Rails.application.credentials.tavily_api_key)
    @api_key = api_key
    @connection = Faraday.new do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
    end
  end

  def search(query:, max_results:, days: nil)
    body = { api_key: @api_key, query: query, max_results: max_results }
    body[:days] = days if days

    response = @connection.post(SEARCH_ENDPOINT, body)
    raise "Tavily search failed (#{response.status}): #{response.body}" unless response.success?

    (response.body["results"] || []).map do |result|
      SearchResult.new(url: result["url"], title: result["title"].to_s)
    end
  end

  def extract(url:)
    response = @connection.post(EXTRACT_ENDPOINT, { api_key: @api_key, urls: [ url ] })
    raise "Tavily extract failed (#{response.status}): #{response.body}" unless response.success?

    results = response.body["results"] || []
    results.first&.dig("raw_content") || ""
  end
end
