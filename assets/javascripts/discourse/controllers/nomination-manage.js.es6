import { ajax } from 'discourse/lib/ajax';

export default Ember.Controller.extend({
  actions: {
    setNominations() {
      const topicId = this.get('model.topicId');
      const callback = this.get('model.callback');
      let usernames = this.get('model.usernames').split(',');

      this.set('loading', true);
      ajax('/election/nominations', {
        type: 'POST',
        data: {
          topic_id: topicId,
          usernames: usernames
        }
      }).then((result) => {
        this.set('loading', false);
        callback(usernames);
        this.send('closeModal');
      })
    }
  }
})
