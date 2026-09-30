# Step 1: turn a resume into characteristics + target_roles.
#
# llm only needs to respond to #extract(prompt:, schema:) — tests pass a
# fake (see app/services/llm_client.rb for the real adapter).
class Profilizer
  PROMPT_TEMPLATE = <<~PROMPT
    You are helping a job seeker figure out what roles to search for. Given
    their resume below, extract their key characteristics (skills, years of
    experience, seniority level, a one-line summary) and suggest a list of
    specific job titles ("target roles") that fit their background —
    including titles they may not have held yet but are realistically
    qualified for (e.g. a Software Engineer's resume might suggest "Senior
    Software Engineer", "Staff Engineer", "Backend Developer").

    Resume:
    ---
    %<resume>s
    ---
  PROMPT

  def self.call(resume_text:, llm:)
    prompt = format(PROMPT_TEMPLATE, resume: resume_text)
    llm.extract(prompt: prompt, schema: ProfileExtraction)
  end
end
