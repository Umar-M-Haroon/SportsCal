// TypeScript types mirroring Swift models

export interface Game {
  idLiveScore?: string
  idEvent?: string
  idLeague?: string
  idHomeTeam?: string
  idAwayTeam?: string
  strHomeTeam: string
  strAwayTeam: string
  strHomeTeamBadge?: string
  strAwayTeamBadge?: string
  intHomeScore?: string
  intAwayScore?: string
  strStatus?: string
  strProgress?: string
  strTimestamp?: string
  lastPlay?: string
  isCompleted?: boolean
  isoDate?: string
  strSport?: string
  strLeague?: string
}

export interface LiveEvent {
  events: Game[]
}

export interface LiveScore {
  nba?: LiveEvent
  mlb?: LiveEvent
  soccer?: LiveEvent
  nfl?: LiveEvent
  nhl?: LiveEvent
  golf?: LiveEvent
  tennis?: LiveEvent
  racing?: LiveEvent
}

export interface Team {
  idTeam?: string
  strTeam?: string
  strTeamShort?: string
  strAlternate?: string
  strTeamBadge?: string
}

export enum Leagues {
  English_Premier_League = 4328,
  English_League_Championship = 4329,
  German_Bundesliga = 4331,
  Serie_A = 4332,
  Ligue_1 = 4334,
  La_Liga = 4335,
  Eredivisie = 4337,
  MLS = 4346,
  Liga_MX = 4350,
  FIFA_World_Cup = 4429,
  UEFA_Champions_League = 4480,
  UEFA_Europa_League = 4481,
  FA_Cup = 4482,
  Copa_del_Rey = 4483,
  Coupe_De_France = 4484,
  DFB_Pokal = 4485,
  UEFA_Nations_League = 4490,
  Copa_America = 4499,
  UEFA_Conference_League = 5071,
  Womens_World_Cup = 4565,
  NFL = 4391,
  NBA = 4387,
  NHL = 4380,
  MLB = 4424,
  PGA = 4425,
  ATP = 4464,
  WTA = 4517,
  Formula1 = 4370
}

export const LeagueNames: Record<Leagues, string> = {
  [Leagues.English_Premier_League]: 'English Premier League',
  [Leagues.English_League_Championship]: 'English Championship',
  [Leagues.German_Bundesliga]: 'Bundesliga',
  [Leagues.Serie_A]: 'Serie A',
  [Leagues.Ligue_1]: 'Ligue 1',
  [Leagues.La_Liga]: 'La Liga',
  [Leagues.Eredivisie]: 'Eredivisie',
  [Leagues.MLS]: 'MLS',
  [Leagues.Liga_MX]: 'Liga MX',
  [Leagues.FIFA_World_Cup]: 'FIFA World Cup',
  [Leagues.UEFA_Champions_League]: 'UEFA Champions League',
  [Leagues.UEFA_Europa_League]: 'UEFA Europa League',
  [Leagues.FA_Cup]: 'FA Cup',
  [Leagues.Copa_del_Rey]: 'Copa Del Rey',
  [Leagues.Coupe_De_France]: 'Coupe De France',
  [Leagues.DFB_Pokal]: 'DFB Pokal',
  [Leagues.UEFA_Nations_League]: 'UEFA Nations League',
  [Leagues.Copa_America]: 'Copa America',
  [Leagues.UEFA_Conference_League]: 'UEFA Conference League',
  [Leagues.NFL]: 'NFL',
  [Leagues.MLB]: 'MLB',
  [Leagues.NHL]: 'NHL',
  [Leagues.NBA]: 'NBA',
  [Leagues.Womens_World_Cup]: "FIFA Women's World Cup",
  [Leagues.PGA]: 'PGA Tour',
  [Leagues.ATP]: 'ATP Tour',
  [Leagues.WTA]: 'WTA Tour',
  [Leagues.Formula1]: 'Formula 1'
}

// Admin-specific types

export interface RedisHealth {
  connected: boolean
  keyCount?: number
  memory?: string
}

export interface JobStatus {
  name: string
  schedule: string
  lastRun?: string
  status: string
}

export interface HealthResponse {
  status: string
  redis: RedisHealth
  jobs: JobStatus[]
  timestamp: string
}

export interface MetricsResponse {
  totalRequests: number
  averageResponseTime: number
  errorRate: number
  timestamp: string
}

export interface RedisKeyInfo {
  key: string
  type: string
  size?: number
  ttl?: number
}

export interface RedisKeysResponse {
  keys: RedisKeyInfo[]
  total: number
}

export interface RedisKeyContentResponse {
  key: string
  type: string
  value: string
  ttl?: number
}

export interface LeagueAnalysis {
  league: string
  leagueId: number
  sport: string
  totalGames: number
  gamesWithoutBadges: number
  gamesWithoutScores: number
  gamesWithoutTimestamps: number
  completeness: number
}

export interface GapSummary {
  totalLeagues: number
  totalGames: number
  overallCompleteness: number
  leaguesWithIssues: number
}

export interface DataGapsResponse {
  leagues: LeagueAnalysis[]
  summary: GapSummary
  timestamp: string
}

export interface LeagueStatsResponse {
  league: string
  leagueId: number
  sport: string
  totalGames: number
  liveGames: number
  completedGames: number
  upcomingGames: number
  teams: string[]
}

export interface InvalidateResponse {
  success: boolean
  message: string
}

export interface RefreshResponse {
  success: boolean
  message: string
  keysRefreshed: string[]
}

export interface TriggerJobResponse {
  success: boolean
  message: string
  jobName: string
}

export interface ForceRefreshResponse {
  success: boolean
  message: string
  keysCleared: string[]
  gamesLoaded: Record<string, number>
}

export type SportType = 'basketball' | 'soccer' | 'hockey' | 'football' | 'baseball' | 'golf' | 'tennis' | 'racing'
