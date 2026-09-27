import type { UserSkill } from '../types';

export interface SkillMatchResult {
  skill: UserSkill;
  score: number;
  matchedKeywords: string[];
}

// Tap hop cac tu dung (stop-words) pho bien can bo qua khi phan tich y dinh
const STOP_WORDS: Set<string> = new Set([
  // Tieng Viet
  'va', 'cua', 'cho', 'la', 'cac', 'nhung', 'de', 'trong', 'voi', 'mot',
  'toi', 'ban', 'hay', 'giup', 'lam', 've', 'nay', 'do', 'duoc', 'khi',
  // Tieng Anh
  'the', 'and', 'for', 'with', 'a', 'an', 'in', 'on', 'at', 'to', 'of',
  'is', 'are', 'this', 'that', 'it', 'me', 'you', 'how', 'what', 'can'
]);

/**
 * Chuan hoa van ban, bo dau tieng Viet de so khop tu khoa khong dau
 */
function normalizeText(text: string): string {
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9\s-_]/g, ' ')
    .trim();
}

/**
 * Trich xuat danh sach tu khoa co y nghia tu truy van cua nguoi dung
 */
export function extractKeywords(query: string): string[] {
  const normalized: string = normalizeText(query);
  const rawTokens: string[] = normalized.split(/\s+/);
  const keywords: string[] = [];

  for (const token of rawTokens) {
    if (token.length >= 2 && !STOP_WORDS.has(token)) {
      keywords.push(token);
    }
  }
  return keywords;
}

/**
 * Tinh diem va tim kiem cac skills phu hop nhat theo y dinh nguoi dung (Find Skill)
 */
export function findMatchingSkills(
  skills: UserSkill[],
  query: string,
  topK: number = 3
): SkillMatchResult[] {
  if (!query.trim() || !skills.length) {
    return [];
  }

  const keywords: string[] = extractKeywords(query);
  if (!keywords.length) {
    return [];
  }

  const results: SkillMatchResult[] = [];

  for (const skill of skills) {
    // Chi xet cac skill dang duoc bat
    if (skill.enabled === false) {
      continue;
    }

    const skillName: string = normalizeText(skill.title);
    const skillTitle: string = normalizeText(skill.title || '');
    const skillDesc: string = normalizeText(skill.description || '');

    let score: number = 0;
    const matched: string[] = [];

    for (const kw of keywords) {
      let hit: boolean = false;

      // Khop chinh xac ten skill
      if (skillName === kw) {
        score += 10;
        hit = true;
      } else if (skillName.includes(kw)) {
        score += 5;
        hit = true;
      }

      // Khop tieu de skill
      if (skillTitle && skillTitle.includes(kw)) {
        score += 3;
        hit = true;
      }

      // Khop mo ta skill
      if (skillDesc && skillDesc.includes(kw)) {
        score += 2;
        hit = true;
      }

      if (hit) {
        matched.push(kw);
      }
    }

    if (score > 0) {
      results.push({
        skill,
        score,
        matchedKeywords: Array.from(new Set(matched))
      });
    }
  }

  // Sap xep giam dan theo diem so
  results.sort((a, b) => b.score - a.score);

  return results.slice(0, topK);
}

/**
 * Dinh dang danh sach skill tinh gon de chen vao prompt cho ChatGPT
 */
export function formatSkillPrompt(matches: SkillMatchResult[]): string {
  if (!matches.length) {
    return '';
  }

  const lines: string[] = matches.map((m) => {
    const desc: string = m.skill.description ? `: ${m.skill.description.slice(0, 150)}` : '';
    return `- [Skill: ${m.skill.title}]${desc}`;
  });

  return `\n\n[Kỹ năng chuyên biệt được đề xuất cho tác vụ này]:\n${lines.join('\n')}\n`;
}
