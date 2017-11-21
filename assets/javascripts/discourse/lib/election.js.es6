const ElectionStatuses = {
  nomination: 1,
  poll: 2,
  closed_poll: 3
};

function formatTime(time) {
  return moment(time).format('MMMM Do, h:mm a');
}

export { ElectionStatuses, formatTime };
