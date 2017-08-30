import { ElectionStatuses } from '../../lib/election';

export default {
  setupComponent(args, component) {
    const statusObj = Object.keys(ElectionStatuses).map(function(k, i){
      return {
        name: k,
        id: ElectionStatuses[k]
      }
    })

    component.set('electionStatuses', statusObj);
  }
}
