import { HealthMonitor } from './HealthMonitor'
import { LiveGames } from './LiveGames'
import { LeagueExplorer } from './LeagueExplorer'
import { DataGaps } from './DataGaps'
import { RedisViewer } from './RedisViewer'
import { TeamsExplorer } from './TeamsExplorer'
import { DebugTools } from './DebugTools'
import { ServerControl } from './ServerControl'
import { Logs } from './Logs'
import { Parity } from './Parity'

export class Dashboard {
  private currentView: string = ''
  private components: Map<string, any> = new Map()
  private mainContent: HTMLElement

  constructor() {
    this.mainContent = document.getElementById('main-content')!

    // Initialize components
    this.components.set('health', new HealthMonitor())
    this.components.set('live', new LiveGames())
    this.components.set('leagues', new LeagueExplorer())
    this.components.set('gaps', new DataGaps())
    this.components.set('redis', new RedisViewer())
    this.components.set('teams', new TeamsExplorer())
    this.components.set('debug', new DebugTools())
    this.components.set('server', new ServerControl())
    this.components.set('logs', new Logs())
    this.components.set('parity', new Parity())

    this.setupNavigation()
    this.showView('health')
  }

  private setupNavigation() {
    const navButtons = document.querySelectorAll('.nav-btn')

    navButtons.forEach(button => {
      button.addEventListener('click', (e) => {
        const view = (e.target as HTMLElement).dataset.view
        if (view) {
          this.showView(view)
        }
      })
    })
  }

  private showView(view: string) {
    if (this.currentView === view) return

    // Update active nav button
    document.querySelectorAll('.nav-btn').forEach(btn => {
      if (btn instanceof HTMLElement) {
        btn.classList.toggle('active', btn.dataset.view === view)
      }
    })

    // Stop current component
    const currentComponent = this.components.get(this.currentView)
    if (currentComponent?.stop) {
      currentComponent.stop()
    }

    // Show new component
    this.currentView = view
    const component = this.components.get(view)

    if (component) {
      this.mainContent.innerHTML = ''
      component.render(this.mainContent)
    }
  }
}
