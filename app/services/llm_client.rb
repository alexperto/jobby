# Thin adapter over OpenAI's chat completions API, called directly via
# Faraday — no OpenAI SDK gem, per plan.md's constraint. Isolating this one
# method is what makes Profilizer/Searcher testable without touching the
# real API: swap in a fake responding to #extract(prompt:, schema:).
class LlmClient
  DEFAULT_MODEL = "gpt-4o-mini"
  ENDPOINT = "https://api.openai.com/v1/chat/completions"

  def initialize(api_key: Rails.application.credentials.openai_api_key, model: DEFAULT_MODEL)
    @api_key = api_key
    @model = model
    @connection = Faraday.new do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
    end
  end

  # schema must respond to .json_schema (a JSON Schema Hash) and
  # .from_hash(parsed_hash) (build an instance from the parsed response).
  def extract(prompt:, schema:)
    response = @connection.post(ENDPOINT) do |req|
      req.headers["Authorization"] = "Bearer #{@api_key}"
      req.body = {
        model: @model,
        messages: [ { role: "user", content: prompt } ],
        response_format: {
          type: "json_schema",
          json_schema: {
            name: schema.name.underscore,
            schema: schema.json_schema,
            strict: true
          }
        }
      }
    end

    raise "OpenAI request failed (#{response.status}): #{response.body}" unless response.success?

    content = response.body.dig("choices", 0, "message", "content")
    raise "OpenAI response had no content" if content.nil?

    schema.from_hash(JSON.parse(content))
  end
end
