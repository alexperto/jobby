class HistoryController < ApplicationController
  PAGE_SIZE = 25

  def index
    requested_page = params[:page].presence&.to_i || 1
    @jobs, total, @page = JobOpportunity.history_page(page: requested_page, page_size: PAGE_SIZE)
    @total_pages = [ 1, (total.to_f / PAGE_SIZE).ceil ].max
  end
end
