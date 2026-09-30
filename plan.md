Create an Agentic AI application.

Goal:

The application will search the web and find job opportunities matching a user's profile.

Configuration: The user will create his profile, provide his resume.
Define some preferences such as minimum salary, city, mode (in-site, remote, hybrid), etc.


Step 1: Profilize
The LLM will extract a list of characteristics from the resume that will be used to come up with potential positions in the market.
For example, the resume might have a Software Engineer profile and skills, the LLM will come up with potential positions based on the experience, such as Senior Software Engineer, Programmer, Developer, etc. This potential positions data will be appended to the user's profile and ultimately could be edited by the user.
Suggest a different name for the potential positions column if you consider there's a better and clearer name



Step 2: Searcher
The agent will use the potential positions data to search the most popular job websites to find potential job oportunities matching the user profile.
Enable an option to set a limit of these oportunities results (10 by default)
Enable an option to set mode filters (in-site, based on the user's preferences)
Always return remote results
Include job oportunities published no older than 2 weeks by default.
The agent must extract important attributes such as job title, published date, company, location, mode (in-site, remote or hybrid), job description summary, salary and other information relevant to be help the next agent to score this result.

Once the searcher obtained the results, it will try to store them in the db, as long as they are not duplicated.


Step 3. Evaluator

This agent will evaluate the results from step 2 and score them based on the user's profile and preferences.
Let's leave this step pending for now, but the idea is to create a criteria to calculate these scores.



Persisting Data:

1. The user profile table
2. Job Oportunities table
    - Company
    - Title
    - Published Date
    - Created Date
    - Description Summary
    - Minimum Requirements
    - Mode
    - Score
    - State (discarded, applied, irrelevant, etc)
    - Website


Technical specifications:
1. Use Ruby and Rails
2. Use OpenIA as the LLM
3. Do not use external libraries for querying the OpenIA API
4. Use tavily library to search, extract or scrap the websites
5. Use a  SQlite database.


Web Application:

1. No login required
2. Profile Page, to configure the user's profile and preferences options.
3. Job Opportunities page. Include a button to trigger the agent and display the results
4. History page, display all job opportunities records, using pagination.
