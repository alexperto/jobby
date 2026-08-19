module ApplicationHelper
  SAFE_URL_SCHEME = %r{\Ahttps?://}i

  # Renders a real link only for an http(s) url; otherwise renders plain
  # text. This is the render-time backstop for JobOpportunity#url — that
  # column is validated, but the validation is bypassable (insert!,
  # update_columns, ...), so this is what actually stands between
  # untrusted web-scraped data and a link_to href.
  def safe_external_link_to(text, url, **options)
    if url.to_s.match?(SAFE_URL_SCHEME)
      link_to text, url, **options
    else
      content_tag(:span, text)
    end
  end
end
