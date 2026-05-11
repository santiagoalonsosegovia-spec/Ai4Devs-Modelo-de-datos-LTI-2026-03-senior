-- =============================================================
-- Migration: add-job-application-flow (supplement)
-- Generated: 2026-05-11
--
-- Completes 20260511213704_ats_full_schema with:
--   1. Four FK indexes omitted from the initial migration
--   2. CHECK constraints (Prisma DSL does not generate these)
-- =============================================================

-- InterviewStep.interviewTypeId
CREATE INDEX "InterviewStep_interviewTypeId_idx"
    ON "InterviewStep"("interviewTypeId");

-- Position.interviewFlowId
CREATE INDEX "Position_interviewFlowId_idx"
    ON "Position"("interviewFlowId");

-- Position.contactEmployeeId
CREATE INDEX "Position_contactEmployeeId_idx"
    ON "Position"("contactEmployeeId");

-- Interview.interviewStepId
CREATE INDEX "Interview_interviewStepId_idx"
    ON "Interview"("interviewStepId");

-- Position: salary coherence
ALTER TABLE "Position"
    ADD CONSTRAINT "Position_salaryMin_check"
        CHECK ("salaryMin" IS NULL OR "salaryMin" >= 0),
    ADD CONSTRAINT "Position_salaryRange_check"
        CHECK ("salaryMax" IS NULL OR "salaryMin" IS NULL
               OR "salaryMax" >= "salaryMin");

-- Interview: score on a 0-10 scale
ALTER TABLE "Interview"
    ADD CONSTRAINT "Interview_score_check"
        CHECK ("score" IS NULL OR ("score" >= 0 AND "score" <= 10));
