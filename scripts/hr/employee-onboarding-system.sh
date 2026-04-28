#!/usr/bin/env bash
# @file scripts/hr/employee-onboarding-system.sh
# @module hr/people-ops
# @description Employee onboarding, lifecycle, and HR management system
# @governance HR-001: Manage employee lifecycle and performance
# @usage employee-onboarding-system.sh [--setup|--onboard|--offboard] [--output ./employees.json]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Employee onboarding system failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
OPERATION="${1:-setup}"
OUTPUT_FILE="${2:-.}/employee-directory.json"
REPORT_ID="HR-$(date +%Y%m%d-%H%M%S)"
GENERATION_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "═══════════════════════════════════════════════════════"
log_info "EMPLOYEE ONBOARDING & HR MANAGEMENT SYSTEM"
log_info "═══════════════════════════════════════════════════════"
log_info "Report ID: ${REPORT_ID}"
log_info "Operation: ${OPERATION}"
echo

# Initialize configuration
init_config() {
  cat > "${OUTPUT_FILE}" <<EOF
{
  "report_id": "${REPORT_ID}",
  "timestamp": "${GENERATION_TIME}",
  "employees": [],
  "departments": [],
  "onboarding_workflows": [],
  "performance_data": {},
  "hr_analytics": {}
}
EOF
}

# ============================================================================
# DEPARTMENT STRUCTURE
# ============================================================================

define_departments() {
  log_info "Defining organizational departments..."
  
  jq ".departments = [
    {
      \"department_id\": \"DEPT-001\",
      \"name\": \"Engineering\",
      \"manager_id\": \"EMP-001\",
      \"manager_name\": \"Alice Chen\",
      \"headcount\": 45,
      \"budget\": 3600000,
      \"reports_to\": \"CTO\",
      \"sub_departments\": [
        \"Backend Services\",
        \"Frontend\",
        \"DevOps\",
        \"QA Automation\"
      ]
    },
    {
      \"department_id\": \"DEPT-002\",
      \"name\": \"Product\",
      \"manager_id\": \"EMP-002\",
      \"manager_name\": \"Bob Martinez\",
      \"headcount\": 12,
      \"budget\": 900000,
      \"reports_to\": \"VP Product\",
      \"sub_departments\": [
        \"Product Management\",
        \"Design\",
        \"Research\"
      ]
    },
    {
      \"department_id\": \"DEPT-003\",
      \"name\": \"Sales & Marketing\",
      \"manager_id\": \"EMP-003\",
      \"manager_name\": \"Carol Smith\",
      \"headcount\": 28,
      \"budget\": 1680000,
      \"reports_to\": \"COO\",
      \"sub_departments\": [
        \"Sales\",
        \"Marketing\",
        \"Business Development\"
      ]
    },
    {
      \"department_id\": \"DEPT-004\",
      \"name\": \"Finance & Operations\",
      \"manager_id\": \"EMP-004\",
      \"manager_name\": \"David Lee\",
      \"headcount\": 8,
      \"budget\": 600000,
      \"reports_to\": \"CFO\",
      \"sub_departments\": [
        \"Finance\",
        \"HR\",
        \"Legal\"
      ]
    }
  ]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ 4 departments defined"
}

# ============================================================================
# EMPLOYEE PROFILES
# ============================================================================

create_employees() {
  log_info "Creating employee profiles..."
  
  # Executive: Engineering Leader
  jq ".employees += [{
    \"employee_id\": \"EMP-001\",
    \"first_name\": \"Alice\",
    \"last_name\": \"Chen\",
    \"email\": \"alice.chen@company.com\",
    \"phone\": \"+1-555-0101\",
    \"hire_date\": \"2021-03-15\",
    \"title\": \"VP Engineering\",
    \"level\": \"EXECUTIVE\",
    \"department_id\": \"DEPT-001\",
    \"department_name\": \"Engineering\",
    \"manager_id\": \"CEO\",
    \"direct_reports\": 45,
    \"location\": \"San Francisco, CA\",
    \"employment_type\": \"FULL_TIME\",
    \"status\": \"ACTIVE\",
    \"salary\": 250000,
    \"bonus_target_pct\": 50,
    \"equity_grant\": 0.5,
    \"benefits\": {
      \"health_insurance\": \"PLATINUM\",
      \"retirement_401k_match\": 6,
      \"pto_days\": 25,
      \"flexible_work\": true
    },
    \"performance\": {
      \"last_review_date\": \"2026-04-01\",
      \"rating\": \"EXCEEDS_EXPECTATIONS\",
      \"score\": 4.5,
      \"goals_completed\": 8,
      \"goals_total\": 8
    }
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Senior Engineer
  jq ".employees += [{
    \"employee_id\": \"EMP-002\",
    \"first_name\": \"Bob\",
    \"last_name\": \"Martinez\",
    \"email\": \"bob.martinez@company.com\",
    \"phone\": \"+1-555-0102\",
    \"hire_date\": \"2022-06-01\",
    \"title\": \"Senior Backend Engineer\",
    \"level\": \"SENIOR\",
    \"department_id\": \"DEPT-001\",
    \"department_name\": \"Engineering\",
    \"manager_id\": \"EMP-001\",
    \"direct_reports\": 0,
    \"location\": \"Remote\",
    \"employment_type\": \"FULL_TIME\",
    \"status\": \"ACTIVE\",
    \"salary\": 180000,
    \"bonus_target_pct\": 25,
    \"equity_grant\": 0.08,
    \"benefits\": {
      \"health_insurance\": \"GOLD\",
      \"retirement_401k_match\": 4,
      \"pto_days\": 20,
      \"flexible_work\": true
    },
    \"performance\": {
      \"last_review_date\": \"2026-04-01\",
      \"rating\": \"MEETS_EXPECTATIONS\",
      \"score\": 3.8,
      \"goals_completed\": 7,
      \"goals_total\": 8
    }
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Mid-level Engineer
  jq ".employees += [{
    \"employee_id\": \"EMP-005\",
    \"first_name\": \"Emma\",
    \"last_name\": \"Johnson\",
    \"email\": \"emma.johnson@company.com\",
    \"phone\": \"+1-555-0105\",
    \"hire_date\": \"2023-09-01\",
    \"title\": \"Software Engineer\",
    \"level\": \"MID\",
    \"department_id\": \"DEPT-001\",
    \"department_name\": \"Engineering\",
    \"manager_id\": \"EMP-001\",
    \"direct_reports\": 0,
    \"location\": \"San Francisco, CA\",
    \"employment_type\": \"FULL_TIME\",
    \"status\": \"ACTIVE\",
    \"salary\": 140000,
    \"bonus_target_pct\": 20,
    \"equity_grant\": 0.04,
    \"benefits\": {
      \"health_insurance\": \"GOLD\",
      \"retirement_401k_match\": 4,
      \"pto_days\": 20,
      \"flexible_work\": true
    },
    \"performance\": {
      \"last_review_date\": \"2026-04-01\",
      \"rating\": \"MEETS_EXPECTATIONS\",
      \"score\": 3.5,
      \"goals_completed\": 6,
      \"goals_total\": 8
    }
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Recent Hire
  jq ".employees += [{
    \"employee_id\": \"EMP-006\",
    \"first_name\": \"Frank\",
    \"last_name\": \"Wilson\",
    \"email\": \"frank.wilson@company.com\",
    \"phone\": \"+1-555-0106\",
    \"hire_date\": \"2026-03-01\",
    \"title\": \"Junior Software Engineer\",
    \"level\": \"JUNIOR\",
    \"department_id\": \"DEPT-001\",
    \"department_name\": \"Engineering\",
    \"manager_id\": \"EMP-001\",
    \"direct_reports\": 0,
    \"location\": \"Austin, TX\",
    \"employment_type\": \"FULL_TIME\",
    \"status\": \"ACTIVE\",
    \"salary\": 100000,
    \"bonus_target_pct\": 10,
    \"equity_grant\": 0.02,
    \"benefits\": {
      \"health_insurance\": \"BRONZE\",
      \"retirement_401k_match\": 3,
      \"pto_days\": 15,
      \"flexible_work\": true
    },
    \"performance\": {
      \"last_review_date\": null,
      \"rating\": \"PROBATION\",
      \"score\": null,
      \"goals_completed\": 2,
      \"goals_total\": 4
    }
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ 4 employee profiles created"
}

# ============================================================================
# ONBOARDING WORKFLOWS
# ============================================================================

create_onboarding_workflows() {
  log_info "Creating onboarding workflows..."
  
  jq ".onboarding_workflows = [
    {
      \"workflow_id\": \"OB-001\",
      \"employee_id\": \"EMP-006\",
      \"employee_name\": \"Frank Wilson\",
      \"title\": \"Junior Software Engineer\",
      \"department\": \"Engineering\",
      \"onboarding_manager\": \"Alice Chen\",
      \"start_date\": \"2026-03-01\",
      \"status\": \"IN_PROGRESS\",
      \"progress_pct\": 52,
      \"phases\": [
        {
          \"phase\": \"PRE_BOARDING\",
          \"status\": \"COMPLETED\",
          \"duration_hours\": 4,
          \"tasks\": [
            {
              \"task\": \"Background check\",
              \"status\": \"COMPLETED\",
              \"completed_date\": \"2026-02-25\"
            },
            {
              \"task\": \"Equipment ordering\",
              \"status\": \"COMPLETED\",
              \"completed_date\": \"2026-02-28\"
            },
            {
              \"task\": \"Account provisioning\",
              \"status\": \"COMPLETED\",
              \"completed_date\": \"2026-03-01\"
            }
          ]
        },
        {
          \"phase\": \"FIRST_WEEK\",
          \"status\": \"IN_PROGRESS\",
          \"duration_hours\": 20,
          \"tasks\": [
            {
              \"task\": \"Welcome meeting with manager\",
              \"status\": \"COMPLETED\",
              \"completed_date\": \"2026-03-01\"
            },
            {
              \"task\": \"Team introductions\",
              \"status\": \"COMPLETED\",
              \"completed_date\": \"2026-03-02\"
            },
            {
              \"task\": \"Code environment setup\",
              \"status\": \"IN_PROGRESS\",
              \"assigned_to\": \"Bob Martinez\"
            },
            {
              \"task\": \"Code of conduct training\",
              \"status\": \"PENDING\",
              \"due_date\": \"2026-03-05\"
            }
          ]
        },
        {
          \"phase\": \"FIRST_MONTH\",
          \"status\": \"NOT_STARTED\",
          \"duration_hours\": 40,
          \"tasks\": [
            {
              \"task\": \"System architecture overview\",
              \"status\": \"PENDING\",
              \"due_date\": \"2026-03-15\"
            },
            {
              \"task\": \"First code review\",
              \"status\": \"PENDING\",
              \"due_date\": \"2026-03-22\"
            },
            {
              \"task\": \"30-day performance check-in\",
              \"status\": \"PENDING\",
              \"due_date\": \"2026-04-01\"
            }
          ]
        }
      ]
    }
  ]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Onboarding workflows created"
}

# ============================================================================
# PERFORMANCE & COMPENSATION DATA
# ============================================================================

populate_performance_data() {
  log_info "Populating performance and compensation data..."
  
  jq ".performance_data = {
    \"total_headcount\": 93,
    \"active_employees\": 93,
    \"avg_tenure_years\": 2.8,
    \"compensation\": {
      \"total_salary_budget\": 7380000,
      \"avg_salary\": 79355,
      \"median_salary\": 75000,
      \"salary_by_level\": {
        \"executive\": 250000,
        \"senior\": 180000,
        \"mid\": 140000,
        \"junior\": 100000
      }
    },
    \"benefits\": {
      \"health_insurance_cost_per_employee\": 12000,
      \"retirement_match_avg\": 4.5,
      \"avg_pto_days\": 19,
      \"flexible_work_employees\": 87
    },
    \"performance_distribution\": {
      \"exceeds_expectations\": 15,
      \"meets_expectations\": 65,
      \"needs_improvement\": 10,
      \"probation\": 3
    },
    \"attrition\": {
      \"annual_attrition_rate\": 8,
      \"ytd_departures\": 2,
      \"avg_tenure_departing_employees\": 1.2
    }
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Performance and compensation data populated"
}

# ============================================================================
# HR ANALYTICS
# ============================================================================

generate_hr_analytics() {
  log_info "Generating HR analytics..."
  
  jq ".hr_analytics = {
    \"hiring\": {
      \"open_positions\": 12,
      \"pipeline_candidates\": 45,
      \"avg_time_to_fill_days\": 38,
      \"recent_hires_q1\": 6,
      \"quality_of_hire_score\": 4.2
    },
    \"engagement\": {
      \"employee_satisfaction_score\": 4.1,
      \"survey_response_rate\": 87,
      \"top_engagement_drivers\": [
        \"Flexible work arrangement\",
        \"Growth opportunities\",
        \"Team collaboration\",
        \"Work-life balance\"
      ],
      \"areas_for_improvement\": [
        \"Career progression clarity\",
        \"Internal mobility\",
        \"Professional development budget\"
      ]
    },
    \"diversity_equity_inclusion\": {
      \"gender_diversity\": {
        \"male_pct\": 65,
        \"female_pct\": 33,
        \"non_binary_pct\": 2
      },
      \"representation_goals\": {
        \"target_female_leadership_2027\": 40,
        \"current_female_leadership_pct\": 28,
        \"target_urg_representation_2027\": 25,
        \"current_urg_representation_pct\": 18
      }
    },
    \"risks_and_opportunities\": [
      {
        \"category\": \"RETENTION\",
        \"risk\": \"High attrition in engineering (12% vs 8% company avg)\",
        \"action\": \"Review compensation competitiveness and growth paths\"
      },
      {
        \"category\": \"SKILL_GAPS\",
        \"risk\": \"Limited cloud architecture expertise\",
        \"action\": \"Invest in training and strategic hiring\"
      },
      {
        \"category\": \"OPPORTUNITY\",
        \"opportunity\": \"Strong technical depth in backend systems\",
        \"action\": \"Leverage for accelerated product roadmap\"
      }
    ]
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ HR analytics generated"
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
  log_info "Generating employee and HR report..."
  
  echo
  log_info "═══════════════════════════════════════════════════════"
  log_info "EMPLOYEE & HR MANAGEMENT REPORT"
  log_info "═══════════════════════════════════════════════════════"
  
  local total_headcount=$(jq '.performance_data.total_headcount' "${OUTPUT_FILE}")
  local avg_salary=$(jq '.performance_data.compensation.avg_salary' "${OUTPUT_FILE}")
  local attrition=$(jq '.performance_data.attrition.annual_attrition_rate' "${OUTPUT_FILE}")
  
  echo
  log_success "✓ Total Headcount: ${total_headcount} | Avg Salary: \$${avg_salary} | Annual Attrition: ${attrition}%"
  
  echo
  log_info "DEPARTMENTS:"
  jq -r '.departments[] | "  \(.name): \(.headcount) employees | Manager: \(.manager_name)"' "${OUTPUT_FILE}"
  
  echo
  log_info "EMPLOYEE DIRECTORY (Sample):"
  jq -r '.employees[] | "  \(.first_name) \(.last_name) (\(.title)): \(.status)"' "${OUTPUT_FILE}"
  
  echo
  log_info "ONBOARDING STATUS:"
  jq -r '.onboarding_workflows[] | "  \(.employee_name): \(.progress_pct)% complete (Phase: \(.status))"' "${OUTPUT_FILE}"
  
  echo
  log_info "HIRING & ENGAGEMENT:"
  local open_pos=$(jq '.hr_analytics.hiring.open_positions' "${OUTPUT_FILE}")
  local engagement=$(jq '.hr_analytics.engagement.employee_satisfaction_score' "${OUTPUT_FILE}")
  log_info "  Open Positions: ${open_pos} | Employee Satisfaction: ${engagement}/5.0"
}

# Main execution
main() {
  case "${OPERATION}" in
    setup)
      init_config
      define_departments
      create_employees
      create_onboarding_workflows
      populate_performance_data
      generate_hr_analytics
      generate_report
      ;;
    onboard)
      init_config
      create_employees
      create_onboarding_workflows
      generate_report
      ;;
    offboard)
      init_config
      create_employees
      generate_report
      ;;
    *)
      log_error "Unknown operation: ${OPERATION}"
      return 1
      ;;
  esac
  
  log_success "✓ EMPLOYEE ONBOARDING & HR SYSTEM COMPLETE"
  log_info "Output: ${OUTPUT_FILE}"
  
  return 0
}

main
