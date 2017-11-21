import { on, observes } from 'ember-addons/ember-computed-decorators';

export default Ember.Component.extend({
  classNames: 'set-election-time',
  ready: false,

  @on('init')
  setup() {
    const dateTime = this.get('dateTime');
    let time;
    let date;

    if (dateTime) {
      const local = moment(dateTime).local();
      date = local.format('YYYY-MM-DD');
      time = local.format('HH:mm');
      this.setProperties({ date, time });
    }

    Ember.run.scheduleOnce('afterRender', this, () => {
      const timeElementId = this.get('timeElementId');
      const $timePicker = $(`#${timeElementId}`);
      $timePicker.timepicker({ timeFormat: 'H:i' });
      if (time) $timePicker.timepicker('setTime', time);
      $timePicker.change(() => {
        this.set('time', $timePicker.val());
      });
    });

    this.set('ready', true);
  },

  @observes('date', 'time')
  sendTime() {
    const ready = this.get('ready');
    if (ready) {
      const date = this.get('date');
      const time = this.get('time');
      const offset = -new Date().getTimezoneOffset()/60;
      const dateTime = this.get('dateTime');
      const newDateTime = moment(date + 'T' + time).utcOffset(offset).utc().format();
      if (!moment(dateTime).isSame(newDateTime, 'minute')) {
        this.sendAction('setTime', newDateTime);
      }
    }
  },

  mouseDown(e) {
    const disabled = this.get('disabled');
    if (disabled) return e.stopPropagation();
    return true;
  }
});
