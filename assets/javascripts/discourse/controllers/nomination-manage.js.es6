import { ajax } from 'discourse/lib/ajax';

export default Ember.Controller.extend({
  init() {
    this.appEvents.on('header:update-topic', () => {
      this.set('loading', false);
      this.send('closeModal');
    });
  },

  actions: {
    setNominations() {
      const topicId = this.get('model.topicId');
      const usernames = this.get('model.usernames').split(',');

      this.set('loading', true);
      ajax('/election/nominations', {
        type: 'POST',
        data: {
          topic_id: topicId,
          usernames
        }
      })
    }
  }
})
