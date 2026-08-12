/**
 * Google Sheets -> Jira Cloud issue automation
 *
 * Sheet columns:
 * A: ignored, B: Dev summary, C: Subtask summary, D: ignored,
 * E: Jira priority name, F: Estimate MD, G: Jira key,
 * H: Story Points, I: Due date.
 *
 * Required Script Properties:
 * - JIRA_BASE_URL       e.g. https://jira.team.musinsa.com
 * - JIRA_EMAIL
 * - JIRA_API_TOKEN
 *
 * Written automatically:
 * - JIRA_API_BASE_URL
 * - JIRA_DISPLAY_BASE_URL
 * - JIRA_BOARD_ID
 * - JIRA_LAST_PARENT_KEY
 *
 * Optional field-ID overrides:
 * - JIRA_START_DATE_FIELD_ID
 * - JIRA_STORY_POINTS_FIELD_ID
 * - JIRA_ESTIMATE_MD_FIELD_ID
 * - JIRA_SPRINT_FIELD_ID
 */

const MORAE_JIRA = Object.freeze({
  PROJECT_KEY: 'M29CEF',
  TIME_ZONE: 'Asia/Seoul',
  ISSUE_TYPE_NAMES: Object.freeze({
    DEV: Object.freeze(['Dev']),
    SUBTASK: Object.freeze(['Subtask', 'Sub-task']),
  }),
  COLUMNS: Object.freeze({
    DEV_SUMMARY: 2,
    SUBTASK_SUMMARY: 3,
    PRIORITY: 5,
    ESTIMATE_MD: 6,
    ISSUE_KEY: 7,
    STORY_POINTS: 8,
    DUE_DATE: 9,
  }),
  FIELD_NAMES: Object.freeze({
    START_DATE: Object.freeze(['Start date', 'Start Date', '시작 날짜', '시작일']),
    STORY_POINTS: Object.freeze([
      'Story Points',
      'Story point estimate',
      '스토리 포인트',
    ]),
    ESTIMATE_MD: Object.freeze(['Estimate MD', 'Estimate M/D', '예상 MD']),
    SPRINT: Object.freeze(['Sprint', '스프린트']),
  }),
  PREFERRED_FIELD_IDS: Object.freeze({
    START_DATE: 'customfield_10015',
    STORY_POINTS: 'customfield_10036',
    ESTIMATE_MD: 'customfield_12766',
    SPRINT: '',
  }),
  PROPERTY_KEYS: Object.freeze({
    INPUT_BASE_URL: 'JIRA_BASE_URL',
    API_BASE_URL: 'JIRA_API_BASE_URL',
    DISPLAY_BASE_URL: 'JIRA_DISPLAY_BASE_URL',
    EMAIL: 'JIRA_EMAIL',
    TOKEN: 'JIRA_API_TOKEN',
    BOARD_ID: 'JIRA_BOARD_ID',
    LAST_PARENT_KEY: 'JIRA_LAST_PARENT_KEY',
    START_DATE_FIELD_ID: 'JIRA_START_DATE_FIELD_ID',
    STORY_POINTS_FIELD_ID: 'JIRA_STORY_POINTS_FIELD_ID',
    ESTIMATE_MD_FIELD_ID: 'JIRA_ESTIMATE_MD_FIELD_ID',
    SPRINT_FIELD_ID: 'JIRA_SPRINT_FIELD_ID',
  }),
  COLORS: Object.freeze({
    SUCCESS: '#d9ead3',
    ERROR: '#f4cccc',
  }),
});

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('Jira 자동화')
    .addItem('선택 영역으로 Jira 생성', 'createJiraIssuesFromSelection')
    .addSeparator()
    .addItem('인증 테스트', 'testJiraAuthentication')
    .addItem('Sprint 보드 다시 선택', 'resetJiraBoardSelection')
    .addToUi();
}

function testJiraAuthentication() {
  const ui = SpreadsheetApp.getUi();

  try {
    const context = moraeJiraContext_();
    const account = moraeJiraFetchJson_(context, '/rest/api/3/myself');

    if (!account.accountId) {
      throw new Error('Jira 응답에서 accountId를 찾지 못했습니다.');
    }

    ui.alert(
      'Jira 인증 성공',
      `사용자: ${account.displayName || '(이름 없음)'}\n` +
        `API 주소: ${context.apiBaseUrl}`,
      ui.ButtonSet.OK
    );
  } catch (error) {
    ui.alert('Jira 인증 실패', moraeJiraErrorText_(error), ui.ButtonSet.OK);
    throw error;
  }
}

function resetJiraBoardSelection() {
  PropertiesService.getScriptProperties().deleteProperty(
    MORAE_JIRA.PROPERTY_KEYS.BOARD_ID
  );
  SpreadsheetApp.getUi().alert(
    'Sprint 보드 설정을 초기화했습니다. 다음 생성 시 다시 선택합니다.'
  );
}

function createJiraIssuesFromSelection() {
  const ui = SpreadsheetApp.getUi();
  const lock = LockService.getDocumentLock() || LockService.getScriptLock();

  if (!lock.tryLock(1000)) {
    ui.alert('다른 Jira 생성 작업이 실행 중입니다. 잠시 후 다시 시도해주세요.');
    return;
  }

  try {
    const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
    const sheet = spreadsheet.getActiveSheet();
    const range = sheet.getActiveRange();

    if (!range) {
      throw new Error('Jira로 생성할 행을 선택해주세요.');
    }

    const selection = moraeJiraReadSelection_(spreadsheet, sheet, range);
    if (selection.items.length === 0) {
      throw new Error('선택 영역에 생성할 Jira 항목이 없습니다.');
    }
    if (selection.items.every((item) => moraeJiraIssueKey_(item.existingKey))) {
      ui.alert('선택한 모든 행에 이미 Jira 키가 있어 생성하지 않았습니다.');
      return;
    }

    const context = moraeJiraContext_();
    const account = moraeJiraFetchJson_(context, '/rest/api/3/myself');
    if (!account.accountId) {
      throw new Error('인증된 Jira 계정의 accountId를 찾지 못했습니다.');
    }

    const properties = PropertiesService.getScriptProperties();
    const issueTypes = moraeJiraGetIssueTypes_(context);
    const devType = moraeJiraResolveIssueType_(
      issueTypes,
      MORAE_JIRA.ISSUE_TYPE_NAMES.DEV,
      false,
      'Dev'
    );
    const subtaskType = moraeJiraResolveIssueType_(
      issueTypes,
      MORAE_JIRA.ISSUE_TYPE_NAMES.SUBTASK,
      true,
      'Subtask'
    );

    const firstItem = selection.items[0];
    const existingDevKey = moraeJiraIssueKey_(firstItem.existingKey);
    let upperParent = null;

    if (!existingDevKey) {
      const parentPrompt = moraeJiraPromptParentKey_(ui, properties);
      if (parentPrompt.cancelled) return;

      if (parentPrompt.key) {
        upperParent = moraeJiraGetIssue_(context, parentPrompt.key);
        moraeJiraAssertSameProject_(upperParent, parentPrompt.key);
      }
    }

    const sprint = moraeJiraResolveActiveSprint_(context, properties, ui);
    if (!sprint) return;

    const devMetadata = moraeJiraGetCreateFields_(context, devType.id);
    const subtaskMetadata = moraeJiraGetCreateFields_(context, subtaskType.id);
    const devFields = moraeJiraResolveAutomationFields_(
      devMetadata,
      properties,
      'Dev',
      true
    );
    const subtaskFields = moraeJiraResolveAutomationFields_(
      subtaskMetadata,
      properties,
      'Subtask',
      false
    );

    let existingDev = null;
    if (existingDevKey) {
      existingDev = moraeJiraGetIssue_(context, existingDevKey);
      moraeJiraAssertSameProject_(existingDev, existingDevKey);

      const actualType = existingDev.fields && existingDev.fields.issuetype;
      if (!actualType || String(actualType.id) !== String(devType.id)) {
        throw new Error(
          `첫 행의 기존 키 ${existingDevKey}는 '${devType.name}' 타입이 아닙니다.`
        );
      }
    }

    moraeJiraValidateSelection_(
      selection,
      existingDevKey,
      devType,
      subtaskType,
      devMetadata,
      subtaskMetadata,
      devFields,
      subtaskFields,
      account,
      sprint,
      upperParent && upperParent.key
    );

    const confirmation = moraeJiraConfirmationText_(
      selection,
      existingDev,
      upperParent,
      sprint,
      devType,
      subtaskType
    );
    const confirmed = ui.alert(
      'Jira 생성 확인',
      confirmation,
      ui.ButtonSet.YES_NO
    );
    if (confirmed !== ui.Button.YES) return;

    const result = moraeJiraExecuteCreation_(
      context,
      selection,
      account,
      sprint,
      devType,
      subtaskType,
      devMetadata,
      subtaskMetadata,
      devFields,
      subtaskFields,
      upperParent && upperParent.key
    );

    ui.alert(
      'Jira 생성 완료',
      `생성: ${result.created}건\n` +
        `건너뜀: ${result.skipped}건\n` +
        `실패: ${result.failed}건\n` +
        `Dev: ${result.devKey}`,
      ui.ButtonSet.OK
    );
  } catch (error) {
    ui.alert('Jira 생성 실패', moraeJiraErrorText_(error), ui.ButtonSet.OK);
    throw error;
  } finally {
    lock.releaseLock();
  }
}

function moraeJiraReadSelection_(spreadsheet, sheet, range) {
  const startRow = range.getRow();
  const rowCount = range.getNumRows();
  const lastColumn = MORAE_JIRA.COLUMNS.DUE_DATE;
  const rows = sheet.getRange(startRow, 1, rowCount, lastColumn).getValues();
  const resultNotes = sheet
    .getRange(startRow, MORAE_JIRA.COLUMNS.ISSUE_KEY, rowCount, 1)
    .getNotes();
  const items = [];

  rows.forEach((row, index) => {
    const sheetRow = startRow + index;
    const existingKey = moraeJiraText_(row[MORAE_JIRA.COLUMNS.ISSUE_KEY - 1]);
    const devSummary = moraeJiraText_(row[MORAE_JIRA.COLUMNS.DEV_SUMMARY - 1]);
    const subtaskSummary = moraeJiraText_(
      row[MORAE_JIRA.COLUMNS.SUBTASK_SUMMARY - 1]
    );
    const priority = moraeJiraText_(row[MORAE_JIRA.COLUMNS.PRIORITY - 1]);
    const estimateMD = row[MORAE_JIRA.COLUMNS.ESTIMATE_MD - 1];
    const storyPoints = row[MORAE_JIRA.COLUMNS.STORY_POINTS - 1];
    const dueDate = row[MORAE_JIRA.COLUMNS.DUE_DATE - 1];
    const isFirst = index === 0;
    const isCompletelyBlank = !existingKey &&
      !devSummary &&
      !subtaskSummary &&
      !priority &&
      moraeJiraIsBlank_(estimateMD) &&
      moraeJiraIsBlank_(storyPoints) &&
      moraeJiraIsBlank_(dueDate);

    if (!isFirst && isCompletelyBlank) return;

    items.push({
      isFirst,
      sheetRow,
      summary: isFirst ? devSummary : subtaskSummary,
      priority,
      estimateMD,
      storyPoints,
      dueDate,
      existingKey,
      resultNote: resultNotes[index][0] || '',
      sourceUrl: `${spreadsheet.getUrl()}#gid=${sheet.getSheetId()}&range=A${sheetRow}:I${sheetRow}`,
      resultCell: sheet.getRange(sheetRow, MORAE_JIRA.COLUMNS.ISSUE_KEY),
    });
  });

  if (items.length > 0 && !items[0].isFirst) {
    throw new Error('선택한 첫 행을 확인하지 못했습니다. 다시 선택해주세요.');
  }

  return { items };
}

function moraeJiraValidateSelection_(
  selection,
  existingDevKey,
  devType,
  subtaskType,
  devMetadata,
  subtaskMetadata,
  devFields,
  subtaskFields,
  account,
  sprint,
  upperParentKey
) {
  const errors = [];

  selection.items.forEach((item) => {
    const existingKey = moraeJiraIssueKey_(item.existingKey);
    if (existingKey) return;

    const label = `${item.sheetRow}행`;
    const itemErrors = [];
    if (!item.summary) itemErrors.push(`${label}: 제목이 비어 있습니다.`);
    if (!item.priority) itemErrors.push(`${label}: E열 Priority가 비어 있습니다.`);

    try {
      moraeJiraNumber_(item.estimateMD, `${label} F열 Estimate MD`);
    } catch (error) {
      itemErrors.push(moraeJiraErrorText_(error));
    }

    try {
      moraeJiraNumber_(item.storyPoints, `${label} H열 Story Points`);
    } catch (error) {
      itemErrors.push(moraeJiraErrorText_(error));
    }

    try {
      moraeJiraDate_(item.dueDate, `${label} I열 기한`);
    } catch (error) {
      itemErrors.push(moraeJiraErrorText_(error));
    }

    errors.push.apply(errors, itemErrors);
    if (itemErrors.length > 0) return;

    try {
      const metadata = item.isFirst ? devMetadata : subtaskMetadata;
      const automationFields = item.isFirst ? devFields : subtaskFields;
      const issueType = item.isFirst ? devType : subtaskType;
      const parentKey = item.isFirst
        ? upperParentKey
        : (existingDevKey || `${MORAE_JIRA.PROJECT_KEY}-0`);
      const fields = moraeJiraBuildIssueFields_(
        item,
        issueType,
        metadata,
        automationFields,
        account,
        sprint,
        parentKey
      );
      moraeJiraAssertRequiredFields_(metadata, fields, label);
    } catch (error) {
      errors.push(`${label}: ${moraeJiraErrorText_(error)}`);
    }
  });

  if (errors.length > 0) {
    throw new Error(`생성 전 검증에 실패했습니다.\n\n${errors.join('\n')}`);
  }
}

function moraeJiraConfirmationText_(
  selection,
  existingDev,
  upperParent,
  sprint,
  devType,
  subtaskType
) {
  const toCreate = selection.items.filter(
    (item) => !moraeJiraIssueKey_(item.existingKey)
  );
  const skipped = selection.items.length - toCreate.length;
  const first = selection.items[0];
  const devLabel = existingDev
    ? `${existingDev.key} (기존 Dev 사용)`
    : `${first.summary} (새 ${devType.name})`;
  const upperParentLabel = upperParent
    ? `${upperParent.key} · ${upperParent.fields.summary}`
    : '(없음)';
  const previews = toCreate.slice(0, 12).map((item) => {
    const type = item.isFirst ? devType.name : subtaskType.name;
    return `• ${item.sheetRow}행 [${type}] ${item.summary}`;
  });

  if (toCreate.length > 12) {
    previews.push(`• 그 외 ${toCreate.length - 12}건`);
  }

  return [
    `프로젝트: ${MORAE_JIRA.PROJECT_KEY}`,
    `상위 Task: ${upperParentLabel}`,
    `Dev: ${devLabel}`,
    `Sprint: ${sprint.name} (#${sprint.id})`,
    `생성: ${toCreate.length}건 / 건너뜀: ${skipped}건`,
    '',
    previews.join('\n'),
    '',
    '생성하시겠습니까?',
  ].join('\n');
}

function moraeJiraExecuteCreation_(
  context,
  selection,
  account,
  sprint,
  devType,
  subtaskType,
  devMetadata,
  subtaskMetadata,
  devFields,
  subtaskFields,
  upperParentKey
) {
  let created = 0;
  let skipped = 0;
  let failed = 0;
  const first = selection.items[0];
  let devKey = moraeJiraIssueKey_(first.existingKey);
  let devWasCreated = false;

  if (devKey) {
    skipped += 1;
  } else {
    try {
      const fields = moraeJiraBuildIssueFields_(
        first,
        devType,
        devMetadata,
        devFields,
        account,
        sprint,
        upperParentKey
      );
      const result = moraeJiraCreateIssue_(context, fields);
      devKey = result.key;
      moraeJiraWriteSuccess_(first.resultCell, devKey, context.displayBaseUrl);
      created += 1;
      devWasCreated = true;
    } catch (error) {
      moraeJiraWriteError_(first.resultCell, error);
      throw new Error(
        `Dev 생성에 실패하여 Subtask를 생성하지 않았습니다.\n${moraeJiraErrorText_(error)}`
      );
    }
  }

  const shouldRepairSprint = String(first.resultNote || '')
    .startsWith('Sprint 연결 실패:');
  if (!devFields.sprint && (devWasCreated || shouldRepairSprint)) {
    try {
      moraeJiraAddIssuesToSprint_(context, sprint.id, [devKey]);
      first.resultCell.clearNote();
    } catch (error) {
      first.resultCell.setNote(`Sprint 연결 실패: ${moraeJiraErrorText_(error)}`);
      throw new Error(
        `${devKey}를 활성 Sprint에 연결하지 못했습니다. ` +
          'Dev 키는 G열에 보존했습니다.\n' +
          moraeJiraErrorText_(error)
      );
    }
  }

  selection.items.slice(1).forEach((item) => {
    if (moraeJiraIssueKey_(item.existingKey)) {
      skipped += 1;
      return;
    }

    try {
      const fields = moraeJiraBuildIssueFields_(
        item,
        subtaskType,
        subtaskMetadata,
        subtaskFields,
        account,
        sprint,
        devKey
      );
      const result = moraeJiraCreateIssue_(context, fields);
      moraeJiraWriteSuccess_(item.resultCell, result.key, context.displayBaseUrl);
      created += 1;
    } catch (error) {
      moraeJiraWriteError_(item.resultCell, error);
      failed += 1;
    }
  });

  SpreadsheetApp.flush();
  return { created, skipped, failed, devKey };
}

function moraeJiraBuildIssueFields_(
  item,
  issueType,
  metadata,
  automationFields,
  account,
  sprint,
  parentKey
) {
  const fields = {
    project: { key: MORAE_JIRA.PROJECT_KEY },
    summary: item.summary,
    issuetype: { id: String(issueType.id) },
    assignee: { id: account.accountId },
    reporter: { id: account.accountId },
    priority: moraeJiraPriorityValue_(metadata, item.priority),
    description: moraeJiraLinkDocument_(item.sourceUrl),
    duedate: moraeJiraDate_(item.dueDate, `${item.sheetRow}행 I열 기한`),
  };

  if (parentKey) fields.parent = { key: parentKey };

  fields[automationFields.startDate.fieldId] = Utilities.formatDate(
    new Date(),
    MORAE_JIRA.TIME_ZONE,
    'yyyy-MM-dd'
  );
  fields[automationFields.storyPoints.fieldId] = moraeJiraFieldNumber_(
    automationFields.storyPoints,
    moraeJiraNumber_(item.storyPoints, `${item.sheetRow}행 H열 Story Points`)
  );
  fields[automationFields.estimateMD.fieldId] = moraeJiraFieldNumber_(
    automationFields.estimateMD,
    moraeJiraNumber_(item.estimateMD, `${item.sheetRow}행 F열 Estimate MD`)
  );

  // Sprint is set on Dev when the create screen exposes the field. The Agile
  // endpoint is also called after creation, which is the authoritative fallback.
  if (item.isFirst && automationFields.sprint) {
    fields[automationFields.sprint.fieldId] = Number(sprint.id);
  }

  return fields;
}

function moraeJiraCreateIssue_(context, fields) {
  const result = moraeJiraFetchJson_(context, '/rest/api/3/issue', {
    method: 'post',
    payload: JSON.stringify({ fields }),
  });

  if (!result.key) {
    throw new Error('Jira 생성 응답에 이슈 키가 없습니다.');
  }
  return result;
}

function moraeJiraAddIssuesToSprint_(context, sprintId, issueKeys) {
  moraeJiraFetchJson_(
    context,
    `/rest/agile/1.0/sprint/${encodeURIComponent(String(sprintId))}/issue`,
    {
      method: 'post',
      payload: JSON.stringify({ issues: issueKeys }),
      allowEmptyResponse: true,
    }
  );
}

function moraeJiraGetIssueTypes_(context) {
  const result = [];
  let startAt = 0;

  while (true) {
    const data = moraeJiraFetchJson_(
      context,
      `/rest/api/3/issue/createmeta/${encodeURIComponent(MORAE_JIRA.PROJECT_KEY)}` +
        `/issuetypes?startAt=${startAt}&maxResults=50`
    );
    const page = data.issueTypes || [];
    result.push.apply(result, page);
    startAt += page.length;
    if (page.length === 0 || startAt >= Number(data.total || result.length)) break;
  }

  return result;
}

function moraeJiraGetCreateFields_(context, issueTypeId) {
  const result = [];
  let startAt = 0;

  while (true) {
    const data = moraeJiraFetchJson_(
      context,
      `/rest/api/3/issue/createmeta/${encodeURIComponent(MORAE_JIRA.PROJECT_KEY)}` +
        `/issuetypes/${encodeURIComponent(String(issueTypeId))}` +
        `?startAt=${startAt}&maxResults=50`
    );
    const page = data.fields || [];
    result.push.apply(result, page);
    startAt += page.length;
    if (page.length === 0 || startAt >= Number(data.total || result.length)) break;
  }

  return result;
}

function moraeJiraResolveIssueType_(types, aliases, shouldBeSubtask, label) {
  const normalizedAliases = aliases.map(moraeJiraNormalizeName_);
  const candidates = types.filter((type) => {
    return Boolean(type.subtask) === shouldBeSubtask &&
      normalizedAliases.includes(moraeJiraNormalizeName_(type.name));
  });

  if (candidates.length !== 1) {
    const available = types
      .filter((type) => Boolean(type.subtask) === shouldBeSubtask)
      .map((type) => `${type.name} (${type.id})`)
      .join(', ');
    throw new Error(
      `'${label}' 이슈 타입을 하나로 확인할 수 없습니다. ` +
        `사용 가능한 타입: ${available || '(없음)'}`
    );
  }
  return candidates[0];
}

function moraeJiraResolveAutomationFields_(metadata, properties, typeLabel, includeSprint) {
  const keys = MORAE_JIRA.PROPERTY_KEYS;
  const fields = {
    startDate: moraeJiraResolveField_(
      metadata,
      properties.getProperty(keys.START_DATE_FIELD_ID),
      MORAE_JIRA.PREFERRED_FIELD_IDS.START_DATE,
      MORAE_JIRA.FIELD_NAMES.START_DATE,
      `${typeLabel} 시작 날짜`
    ),
    storyPoints: moraeJiraResolveField_(
      metadata,
      properties.getProperty(keys.STORY_POINTS_FIELD_ID),
      MORAE_JIRA.PREFERRED_FIELD_IDS.STORY_POINTS,
      MORAE_JIRA.FIELD_NAMES.STORY_POINTS,
      `${typeLabel} Story Points`
    ),
    estimateMD: moraeJiraResolveField_(
      metadata,
      properties.getProperty(keys.ESTIMATE_MD_FIELD_ID),
      MORAE_JIRA.PREFERRED_FIELD_IDS.ESTIMATE_MD,
      MORAE_JIRA.FIELD_NAMES.ESTIMATE_MD,
      `${typeLabel} Estimate MD`
    ),
    sprint: null,
  };

  if (includeSprint) {
    fields.sprint = moraeJiraResolveField_(
      metadata,
      properties.getProperty(keys.SPRINT_FIELD_ID),
      MORAE_JIRA.PREFERRED_FIELD_IDS.SPRINT,
      MORAE_JIRA.FIELD_NAMES.SPRINT,
      `${typeLabel} Sprint`,
      true
    );
  }

  ['assignee', 'reporter', 'priority', 'description', 'duedate'].forEach((id) => {
    if (!moraeJiraFieldById_(metadata, id)) {
      throw new Error(
        `${typeLabel} 생성 화면에 '${id}' 필드가 없습니다. ` +
          'Jira 프로젝트의 Create Screen 설정을 확인해주세요.'
      );
    }
  });

  return fields;
}

function moraeJiraResolveField_(
  metadata,
  overrideId,
  preferredId,
  aliases,
  label,
  optional
) {
  const explicitId = moraeJiraText_(overrideId);
  if (explicitId) {
    const explicit = moraeJiraFieldById_(metadata, explicitId);
    if (!explicit) {
      throw new Error(
        `${label} 필드 ${explicitId}가 해당 이슈 타입의 Create Screen에 없습니다.`
      );
    }
    return explicit;
  }

  if (preferredId) {
    const preferred = moraeJiraFieldById_(metadata, preferredId);
    if (preferred) return preferred;
  }

  const normalizedAliases = aliases.map(moraeJiraNormalizeName_);
  const candidates = metadata.filter((field) => {
    return normalizedAliases.includes(moraeJiraNormalizeName_(field.name));
  });

  if (candidates.length === 1) return candidates[0];
  if (optional && candidates.length === 0) return null;

  if (candidates.length > 1) {
    throw new Error(
      `${label} 필드가 여러 개입니다: ` +
        candidates.map((field) => `${field.name} (${field.fieldId})`).join(', ') +
        '. Script Properties에 정확한 필드 ID를 지정해주세요.'
    );
  }

  throw new Error(
    `${label} 필드를 찾지 못했습니다. Jira Create Screen에 필드를 추가하거나 ` +
      'Script Properties에 정확한 필드 ID를 지정해주세요.'
  );
}

function moraeJiraPriorityValue_(metadata, input) {
  const priority = moraeJiraFieldById_(metadata, 'priority');
  const requested = moraeJiraNormalizeName_(input);
  const allowed = (priority && priority.allowedValues) || [];
  const match = allowed.find((value) => {
    return moraeJiraNormalizeName_(value.name || value.value) === requested;
  });

  if (!match) {
    const names = allowed.map((value) => value.name || value.value).filter(Boolean);
    throw new Error(
      `Jira Priority '${input}'을 찾지 못했습니다. ` +
        `사용 가능 값: ${names.join(', ') || '(메타데이터에 값 없음)'}`
    );
  }

  return match.id ? { id: String(match.id) } : { name: match.name || match.value };
}

function moraeJiraAssertRequiredFields_(metadata, fields, rowLabel) {
  const missing = metadata.filter((field) => {
    if (!field.required || field.hasDefaultValue) return false;
    const id = field.fieldId || field.key;
    return !Object.prototype.hasOwnProperty.call(fields, id) ||
      fields[id] === null || fields[id] === '';
  });

  if (missing.length > 0) {
    throw new Error(
      `${rowLabel}의 필수 Jira 필드를 자동 입력할 수 없습니다: ` +
        missing.map((field) => `${field.name} (${field.fieldId})`).join(', ')
    );
  }
}

function moraeJiraResolveActiveSprint_(context, properties, ui) {
  const propertyKey = MORAE_JIRA.PROPERTY_KEYS.BOARD_ID;
  let boardId = moraeJiraText_(properties.getProperty(propertyKey));

  if (!boardId) {
    const boards = moraeJiraGetBoards_(context);
    if (boards.length === 0) {
      throw new Error(
        `${MORAE_JIRA.PROJECT_KEY} 프로젝트에서 접근 가능한 Scrum 보드를 찾지 못했습니다.`
      );
    }

    if (boards.length === 1) {
      boardId = String(boards[0].id);
    } else {
      const selected = moraeJiraPromptId_(
        ui,
        'Sprint 보드 선택',
        '사용할 Scrum 보드 ID를 입력하세요.',
        boards
      );
      if (!selected) return null;
      boardId = selected;
    }
    properties.setProperty(propertyKey, boardId);
  }

  const sprints = moraeJiraGetActiveSprints_(context, boardId);
  if (sprints.length === 0) {
    throw new Error(
      `보드 ${boardId}에 활성 Sprint가 없습니다. ` +
        '다른 보드를 쓰려면 메뉴에서 Sprint 보드를 다시 선택해주세요.'
    );
  }

  if (sprints.length === 1) return sprints[0];

  const sprintId = moraeJiraPromptId_(
    ui,
    '활성 Sprint 선택',
    '활성 Sprint가 여러 개입니다. 사용할 Sprint ID를 입력하세요.',
    sprints
  );
  if (!sprintId) return null;
  return sprints.find((sprint) => String(sprint.id) === sprintId);
}

function moraeJiraGetBoards_(context) {
  const result = [];
  let startAt = 0;

  while (true) {
    const data = moraeJiraFetchJson_(
      context,
      '/rest/agile/1.0/board' +
        `?projectKeyOrId=${encodeURIComponent(MORAE_JIRA.PROJECT_KEY)}` +
        `&type=scrum&startAt=${startAt}&maxResults=50`
    );
    const page = data.values || [];
    result.push.apply(result, page);
    startAt += page.length;
    if (data.isLast || page.length === 0 || startAt >= Number(data.total || result.length)) {
      break;
    }
  }
  return result;
}

function moraeJiraGetActiveSprints_(context, boardId) {
  const result = [];
  let startAt = 0;

  while (true) {
    const data = moraeJiraFetchJson_(
      context,
      `/rest/agile/1.0/board/${encodeURIComponent(String(boardId))}/sprint` +
        `?state=active&startAt=${startAt}&maxResults=50`
    );
    const page = data.values || [];
    result.push.apply(result, page);
    startAt += page.length;
    if (data.isLast || page.length === 0 || startAt >= Number(data.total || result.length)) {
      break;
    }
  }
  return result;
}

function moraeJiraPromptId_(ui, title, message, values) {
  const options = values.map((value) => `${value.id}: ${value.name}`).join('\n');
  const response = ui.prompt(title, `${message}\n\n${options}`, ui.ButtonSet.OK_CANCEL);
  if (response.getSelectedButton() !== ui.Button.OK) return null;

  const id = moraeJiraText_(response.getResponseText());
  if (!values.some((value) => String(value.id) === id)) {
    throw new Error(`목록에 없는 ID입니다: ${id}`);
  }
  return id;
}

function moraeJiraPromptParentKey_(ui, properties) {
  const propertyKey = MORAE_JIRA.PROPERTY_KEYS.LAST_PARENT_KEY;
  const previous = moraeJiraText_(properties.getProperty(propertyKey));
  const response = ui.prompt(
    '상위 Task 설정',
    `새 Dev의 상위 Jira 키를 입력하세요.\n` +
      `직전 값: ${previous || '(없음)'}\n\n` +
      '빈 값: 직전 값 사용 / - 입력: 상위 Task 없음',
    ui.ButtonSet.OK_CANCEL
  );

  if (response.getSelectedButton() !== ui.Button.OK) {
    return { cancelled: true, key: null };
  }

  const typed = moraeJiraText_(response.getResponseText());
  if (typed === '-') {
    properties.deleteProperty(propertyKey);
    return { cancelled: false, key: null };
  }

  const key = String(typed || previous).toUpperCase();
  if (key && !moraeJiraIssueKey_(key)) {
    throw new Error(`올바른 Jira 키 형식이 아닙니다: ${key}`);
  }
  if (key) properties.setProperty(propertyKey, key);
  return { cancelled: false, key: key || null };
}

function moraeJiraGetIssue_(context, key) {
  return moraeJiraFetchJson_(
    context,
    `/rest/api/3/issue/${encodeURIComponent(key)}` +
      '?fields=summary,project,issuetype,status'
  );
}

function moraeJiraAssertSameProject_(issue, key) {
  const project = issue.fields && issue.fields.project;
  if (!project || project.key !== MORAE_JIRA.PROJECT_KEY) {
    throw new Error(
      `${key}는 ${MORAE_JIRA.PROJECT_KEY} 프로젝트의 이슈가 아닙니다.`
    );
  }
}

function moraeJiraContext_() {
  const properties = PropertiesService.getScriptProperties();
  const keys = MORAE_JIRA.PROPERTY_KEYS;
  const email = moraeJiraRequiredProperty_(properties, keys.EMAIL).trim();
  const token = moraeJiraRequiredProperty_(properties, keys.TOKEN).trim();
  const inputBaseUrl = moraeJiraNormalizeBaseUrl_(
    moraeJiraRequiredProperty_(properties, keys.INPUT_BASE_URL)
  );
  let apiBaseUrl = moraeJiraText_(properties.getProperty(keys.API_BASE_URL));
  let displayBaseUrl = moraeJiraText_(
    properties.getProperty(keys.DISPLAY_BASE_URL)
  );

  if (!apiBaseUrl || !moraeJiraIsAtlassianCloudUrl_(apiBaseUrl)) {
    const site = moraeJiraDiscoverSite_(inputBaseUrl);
    apiBaseUrl = site.apiBaseUrl;
    displayBaseUrl = site.displayBaseUrl;
    properties.setProperty(keys.API_BASE_URL, apiBaseUrl);
    properties.setProperty(keys.DISPLAY_BASE_URL, displayBaseUrl);
  }

  return {
    apiBaseUrl: moraeJiraNormalizeBaseUrl_(apiBaseUrl),
    displayBaseUrl: moraeJiraNormalizeBaseUrl_(displayBaseUrl || inputBaseUrl),
    email,
    token,
  };
}

function moraeJiraDiscoverSite_(inputBaseUrl) {
  const response = UrlFetchApp.fetch(`${inputBaseUrl}/rest/api/3/serverInfo`, {
    method: 'get',
    headers: { Accept: 'application/json' },
    muteHttpExceptions: true,
    followRedirects: true,
    validateHttpsCertificates: true,
  });
  const status = response.getResponseCode();
  const body = response.getContentText();

  if (status < 200 || status >= 300) {
    throw new Error(
      `Jira 사이트 정보 조회 실패 (${status}): ${moraeJiraApiError_(body)}`
    );
  }

  const info = moraeJiraParseJson_(body, 'Jira 사이트 정보');
  const apiBaseUrl = moraeJiraNormalizeBaseUrl_(info.baseUrl || '');
  const displayBaseUrl = moraeJiraNormalizeBaseUrl_(info.displayUrl || inputBaseUrl);

  if (String(info.deploymentType).toLowerCase() !== 'cloud') {
    throw new Error(`Jira Cloud 사이트가 아닙니다: ${info.deploymentType || '(알 수 없음)'}`);
  }
  if (!moraeJiraIsAtlassianCloudUrl_(apiBaseUrl)) {
    throw new Error(`안전한 Atlassian Cloud API 주소가 아닙니다: ${apiBaseUrl}`);
  }

  return { apiBaseUrl, displayBaseUrl };
}

function moraeJiraFetchJson_(context, path, requestOptions) {
  const options = requestOptions || {};
  const credentials = Utilities.base64Encode(
    `${context.email}:${context.token}`,
    Utilities.Charset.UTF_8
  );
  const fetchOptions = {
    method: options.method || 'get',
    headers: {
      Authorization: `Basic ${credentials}`,
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
    muteHttpExceptions: true,
    followRedirects: false,
    validateHttpsCertificates: true,
  };
  if (options.payload !== undefined) fetchOptions.payload = options.payload;

  const response = UrlFetchApp.fetch(
    `${context.apiBaseUrl}${path}`,
    fetchOptions
  );
  const status = response.getResponseCode();
  const body = response.getContentText();

  if (status < 200 || status >= 300) {
    if (status === 401) {
      throw new Error('Jira 인증에 실패했습니다. (401)');
    }
    if (status === 403) {
      throw new Error(
        `Jira 권한이 부족합니다. (403) ${moraeJiraApiError_(body)}`
      );
    }
    throw new Error(`Jira API 오류 (${status}): ${moraeJiraApiError_(body)}`);
  }

  if (!body) {
    if (options.allowEmptyResponse) return {};
    throw new Error('Jira API가 빈 응답을 반환했습니다.');
  }
  return moraeJiraParseJson_(body, 'Jira API 응답');
}

function moraeJiraApiError_(body) {
  try {
    const parsed = JSON.parse(body || '{}');
    const messages = parsed.errorMessages || [];
    const fieldErrors = parsed.errors
      ? Object.keys(parsed.errors).map((key) => `${key}: ${parsed.errors[key]}`)
      : [];
    const combined = messages.concat(fieldErrors).join(' / ');
    return combined || String(body || '').substring(0, 500) || '(내용 없음)';
  } catch (error) {
    return String(body || '').substring(0, 500) || '(내용 없음)';
  }
}

function moraeJiraParseJson_(body, label) {
  try {
    return JSON.parse(body);
  } catch (error) {
    throw new Error(`${label}이 올바른 JSON 형식이 아닙니다.`);
  }
}

function moraeJiraWriteSuccess_(cell, key, displayBaseUrl) {
  const value = SpreadsheetApp.newRichTextValue()
    .setText(key)
    .setLinkUrl(`${displayBaseUrl}/browse/${encodeURIComponent(key)}`)
    .build();
  cell.setRichTextValue(value);
  cell.setBackground(MORAE_JIRA.COLORS.SUCCESS);
  cell.clearNote();
}

function moraeJiraWriteError_(cell, error) {
  cell.setValue('ERROR');
  cell.setBackground(MORAE_JIRA.COLORS.ERROR);
  cell.setNote(moraeJiraErrorText_(error).substring(0, 1000));
}

function moraeJiraLinkDocument_(url) {
  return {
    type: 'doc',
    version: 1,
    content: [
      {
        type: 'paragraph',
        content: [
          {
            type: 'text',
            text: url,
            marks: [{ type: 'link', attrs: { href: url } }],
          },
        ],
      },
    ],
  };
}

function moraeJiraFieldNumber_(field, value) {
  if (field.schema && field.schema.type === 'string') return String(value);
  return value;
}

function moraeJiraNumber_(value, label) {
  if (moraeJiraIsBlank_(value)) {
    throw new Error(`${label} 값이 비어 있습니다.`);
  }
  const number = typeof value === 'number'
    ? value
    : Number(String(value).trim().replace(/,/g, ''));
  if (!Number.isFinite(number) || number < 0) {
    throw new Error(`${label}은 0 이상의 숫자여야 합니다: ${value}`);
  }
  return number;
}

function moraeJiraDate_(value, label) {
  if (moraeJiraIsBlank_(value)) {
    throw new Error(`${label} 값이 비어 있습니다.`);
  }
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return Utilities.formatDate(value, MORAE_JIRA.TIME_ZONE, 'yyyy-MM-dd');
  }
  const text = moraeJiraText_(value);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    throw new Error(`${label}은 날짜 셀 또는 YYYY-MM-DD 형식이어야 합니다: ${text}`);
  }
  return text;
}

function moraeJiraFieldById_(metadata, id) {
  return metadata.find((field) => {
    return String(field.fieldId || field.key) === String(id);
  }) || null;
}

function moraeJiraIssueKey_(value) {
  const text = moraeJiraText_(value).toUpperCase();
  return /^[A-Z][A-Z0-9_]*-\d+$/.test(text) ? text : null;
}

function moraeJiraNormalizeName_(value) {
  return moraeJiraText_(value).toLowerCase().replace(/\s+/g, ' ');
}

function moraeJiraNormalizeBaseUrl_(value) {
  const normalized = moraeJiraText_(value).replace(/\/+$/, '');
  if (!normalized.startsWith('https://')) {
    throw new Error(`Jira 주소는 https://로 시작해야 합니다: ${normalized}`);
  }
  return normalized;
}

function moraeJiraIsAtlassianCloudUrl_(value) {
  return /^https:\/\/[a-z0-9.-]+\.atlassian\.net(?:\/|$)/i.test(value);
}

function moraeJiraRequiredProperty_(properties, key) {
  const value = properties.getProperty(key);
  if (!value || !value.trim()) {
    throw new Error(`Script Property '${key}'이 설정되지 않았습니다.`);
  }
  return value;
}

function moraeJiraText_(value) {
  if (value === null || value === undefined) return '';
  return String(value).trim();
}

function moraeJiraIsBlank_(value) {
  return value === null || value === undefined || moraeJiraText_(value) === '';
}

function moraeJiraErrorText_(error) {
  return error && error.message ? error.message : String(error);
}
